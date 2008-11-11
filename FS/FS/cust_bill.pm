package FS::cust_bill;

use strict;
use vars qw( @ISA $DEBUG $me $conf $money_char );
use vars qw( $invoice_lines @buf ); #yuck
use Fcntl qw(:flock); #for spool_csv
use List::Util qw(min max);
use Date::Format;
use Text::Template 1.20;
use File::Temp 0.14;
use String::ShellQuote;
use HTML::Entities;
use Locale::Country;
use FS::UID qw( datasrc );
use FS::Misc qw( send_email send_fax generate_ps generate_pdf do_print );
use FS::Record qw( qsearch qsearchs dbh );
use FS::cust_main_Mixin;
use FS::cust_main;
use FS::cust_bill_pkg;
use FS::cust_credit;
use FS::cust_pay;
use FS::cust_pkg;
use FS::cust_credit_bill;
use FS::pay_batch;
use FS::cust_pay_batch;
use FS::cust_bill_event;
use FS::part_pkg;
use FS::cust_bill_pay;
use FS::cust_bill_pay_batch;
use FS::part_bill_event;
use FS::payby;

@ISA = qw( FS::cust_main_Mixin FS::Record );

$DEBUG = 0;
$me = '[FS::cust_bill]';

#ask FS::UID to run this stuff for us later
FS::UID->install_callback( sub { 
  $conf = new FS::Conf;
  $money_char = $conf->config('money_char') || '$';  
} );

=head1 NAME

FS::cust_bill - Object methods for cust_bill records

=head1 SYNOPSIS

  use FS::cust_bill;

  $record = new FS::cust_bill \%hash;
  $record = new FS::cust_bill { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

  ( $total_previous_balance, @previous_cust_bill ) = $record->previous;

  @cust_bill_pkg_objects = $cust_bill->cust_bill_pkg;

  ( $total_previous_credits, @previous_cust_credit ) = $record->cust_credit;

  @cust_pay_objects = $cust_bill->cust_pay;

  $tax_amount = $record->tax;

  @lines = $cust_bill->print_text;
  @lines = $cust_bill->print_text $time;

=head1 DESCRIPTION

An FS::cust_bill object represents an invoice; a declaration that a customer
owes you money.  The specific charges are itemized as B<cust_bill_pkg> records
(see L<FS::cust_bill_pkg>).  FS::cust_bill inherits from FS::Record.  The
following fields are currently supported:

=over 4

=item invnum - primary key (assigned automatically for new invoices)

=item custnum - customer (see L<FS::cust_main>)

=item _date - specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=item charged - amount of this invoice

=item printed - deprecated

=item closed - books closed flag, empty or `Y'

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new invoice.  To add the invoice to the database, see L<"insert">.
Invoices are normally created by calling the bill method of a customer object
(see L<FS::cust_main>).

=cut

sub table { 'cust_bill'; }

sub cust_linked { $_[0]->cust_main_custnum; } 
sub cust_unlinked_msg {
  my $self = shift;
  "WARNING: can't find cust_main.custnum ". $self->custnum.
  ' (cust_bill.invnum '. $self->invnum. ')';
}

=item insert

Adds this invoice to the database ("Posts" the invoice).  If there is an error,
returns the error, otherwise returns false.

=item delete

This method now works but you probably shouldn't use it.  Instead, apply a
credit against the invoice.

Using this method to delete invoices outright is really, really bad.  There
would be no record you ever posted this invoice, and there are no check to
make sure charged = 0 or that there are no associated cust_bill_pkg records.

Really, don't use it.

=cut

sub delete {
  my $self = shift;
  return "Can't delete closed invoice" if $self->closed =~ /^Y/i;
  $self->SUPER::delete(@_);
}

=item replace OLD_RECORD

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

Only printed may be changed.  printed is normally updated by calling the
collect method of a customer object (see L<FS::cust_main>).

=cut

#replace can be inherited from Record.pm

# replace_check is now the preferred way to #implement replace data checks
# (so $object->replace() works without an argument)

sub replace_check {
  my( $new, $old ) = ( shift, shift );
  return "Can't change custnum!" unless $old->custnum == $new->custnum;
  #return "Can't change _date!" unless $old->_date eq $new->_date;
  return "Can't change _date!" unless $old->_date == $new->_date;
  return "Can't change charged!" unless $old->charged == $new->charged
                                     || $old->charged == 0;

  '';
}

=item check

Checks all fields to make sure this is a valid invoice.  If there is an error,
returns the error, otherwise returns false.  Called by the insert and replace
methods.

=cut

sub check {
  my $self = shift;

  my $error =
    $self->ut_numbern('invnum')
    || $self->ut_number('custnum')
    || $self->ut_numbern('_date')
    || $self->ut_money('charged')
    || $self->ut_numbern('printed')
    || $self->ut_enum('closed', [ '', 'Y' ])
  ;
  return $error if $error;

  return "Unknown customer"
    unless qsearchs( 'cust_main', { 'custnum' => $self->custnum } );

  $self->_date(time) unless $self->_date;

  $self->printed(0) if $self->printed eq '';

  $self->SUPER::check;
}

=item previous

Returns a list consisting of the total previous balance for this customer, 
followed by the previous outstanding invoices (as FS::cust_bill objects also).

=cut

sub previous {
  my $self = shift;
  my $total = 0;
  my @cust_bill = sort { $a->_date <=> $b->_date }
    grep { $_->owed != 0 && $_->_date < $self->_date }
      qsearch( 'cust_bill', { 'custnum' => $self->custnum } ) 
  ;
  foreach ( @cust_bill ) { $total += $_->owed; }
  $total, @cust_bill;
}

=item cust_bill_pkg

Returns the line items (see L<FS::cust_bill_pkg>) for this invoice.

=cut

sub cust_bill_pkg {
  my $self = shift;
  qsearch( 'cust_bill_pkg', { 'invnum' => $self->invnum } );
}

=item cust_pkg

Returns the packages (see L<FS::cust_pkg>) corresponding to the line items for
this invoice.

=cut

sub cust_pkg {
  my $self = shift;
  my @cust_pkg = map { $_->cust_pkg } $self->cust_bill_pkg;
  my %saw = ();
  grep { ! $saw{$_->pkgnum}++ } @cust_pkg;
}

=item open_cust_bill_pkg

Returns the open line items for this invoice.

Note that cust_bill_pkg with both setup and recur fees are returned as two
separate line items, each with only one fee.

=cut

# modeled after cust_main::open_cust_bill
sub open_cust_bill_pkg {
  my $self = shift;

  # grep { $_->owed > 0 } $self->cust_bill_pkg

  my %other = ( 'recur' => 'setup',
                'setup' => 'recur', );
  my @open = ();
  foreach my $field ( qw( recur setup )) {
    push @open, map  { $_->set( $other{$field}, 0 ); $_; }
                grep { $_->owed($field) > 0 }
                $self->cust_bill_pkg;
  }

  @open;
}

=item cust_bill_event

Returns the completed invoice events (see L<FS::cust_bill_event>) for this
invoice.

=cut

sub cust_bill_event {
  my $self = shift;
  qsearch( 'cust_bill_event', { 'invnum' => $self->invnum } );
}


=item cust_main

Returns the customer (see L<FS::cust_main>) for this invoice.

=cut

sub cust_main {
  my $self = shift;
  qsearchs( 'cust_main', { 'custnum' => $self->custnum } );
}

=item cust_suspend_if_balance_over AMOUNT

Suspends the customer associated with this invoice if the total amount owed on
this invoice and all older invoices is greater than the specified amount.

Returns a list: an empty list on success or a list of errors.

=cut

sub cust_suspend_if_balance_over {
  my( $self, $amount ) = ( shift, shift );
  my $cust_main = $self->cust_main;
  if ( $cust_main->total_owed_date($self->_date) < $amount ) {
    return ();
  } else {
    $cust_main->suspend(@_);
  }
}

=item cust_credit

Depreciated.  See the cust_credited method.

 #Returns a list consisting of the total previous credited (see
 #L<FS::cust_credit>) and unapplied for this customer, followed by the previous
 #outstanding credits (FS::cust_credit objects).

=cut

sub cust_credit {
  use Carp;
  croak "FS::cust_bill->cust_credit depreciated; see ".
        "FS::cust_bill->cust_credit_bill";
  #my $self = shift;
  #my $total = 0;
  #my @cust_credit = sort { $a->_date <=> $b->_date }
  #  grep { $_->credited != 0 && $_->_date < $self->_date }
  #    qsearch('cust_credit', { 'custnum' => $self->custnum } )
  #;
  #foreach (@cust_credit) { $total += $_->credited; }
  #$total, @cust_credit;
}

=item cust_pay

Depreciated.  See the cust_bill_pay method.

#Returns all payments (see L<FS::cust_pay>) for this invoice.

=cut

sub cust_pay {
  use Carp;
  croak "FS::cust_bill->cust_pay depreciated; see FS::cust_bill->cust_bill_pay";
  #my $self = shift;
  #sort { $a->_date <=> $b->_date }
  #  qsearch( 'cust_pay', { 'invnum' => $self->invnum } )
  #;
}

=item cust_bill_pay

Returns all payment applications (see L<FS::cust_bill_pay>) for this invoice.

=cut

sub cust_bill_pay {
  my $self = shift;
  sort { $a->_date <=> $b->_date }
    qsearch( 'cust_bill_pay', { 'invnum' => $self->invnum } );
}

=item cust_credited

Returns all applied credits (see L<FS::cust_credit_bill>) for this invoice.

=cut

sub cust_credited {
  my $self = shift;
  sort { $a->_date <=> $b->_date }
    qsearch( 'cust_credit_bill', { 'invnum' => $self->invnum } )
  ;
}

=item tax

Returns the tax amount (see L<FS::cust_bill_pkg>) for this invoice.

=cut

sub tax {
  my $self = shift;
  my $total = 0;
  my @taxlines = qsearch( 'cust_bill_pkg', { 'invnum' => $self->invnum ,
                                             'pkgnum' => 0 } );
  foreach (@taxlines) { $total += $_->setup; }
  $total;
}

=item owed

Returns the amount owed (still outstanding) on this invoice, which is charged
minus all payment applications (see L<FS::cust_bill_pay>) and credit
applications (see L<FS::cust_credit_bill>).

=cut

sub owed {
  my $self = shift;
  my $balance = $self->charged;
  $balance -= $_->amount foreach ( $self->cust_bill_pay );
  $balance -= $_->amount foreach ( $self->cust_credited );
  $balance = sprintf( "%.2f", $balance);
  $balance =~ s/^\-0\.00$/0.00/; #yay ieee fp
  $balance;
}

=item apply_payments_and_credits

=cut

sub apply_payments_and_credits {
  my $self = shift;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  $self->select_for_update; #mutex

  my @payments = grep { $_->unapplied > 0 } $self->cust_main->cust_pay;
  my @credits  = grep { $_->credited > 0 } $self->cust_main->cust_credit;

  while ( $self->owed > 0 and ( @payments || @credits ) ) {

    my $app = '';
    if ( @payments && @credits ) {

      #decide which goes first by weight of top (unapplied) line item

      my @open_lineitems = $self->open_cust_bill_pkg;

      my $max_pay_weight =
        max( map  { $_->part_pkg->pay_weight || 0 }
             grep { $_ }
             map  { $_->cust_pkg }
	          @open_lineitems
	   );
      my $max_credit_weight =
        max( map  { $_->part_pkg->credit_weight || 0 }
	     grep { $_ } 
             map  { $_->cust_pkg }
                  @open_lineitems
           );

      #if both are the same... payments first?  it has to be something
      if ( $max_pay_weight >= $max_credit_weight ) {
        $app = 'pay';
      } else {
        $app = 'credit';
      }
    
    } elsif ( @payments ) {
      $app = 'pay';
    } elsif ( @credits ) {
      $app = 'credit';
    } else {
      die "guru meditation #12 and 35";
    }

    if ( $app eq 'pay' ) {

      my $payment = shift @payments;

      $app = new FS::cust_bill_pay {
        'paynum'  => $payment->paynum,
	'amount'  => sprintf('%.2f', min( $payment->unapplied, $self->owed ) ),
      };

    } elsif ( $app eq 'credit' ) {

      my $credit = shift @credits;

      $app = new FS::cust_credit_bill {
        'crednum' => $credit->crednum,
	'amount'  => sprintf('%.2f', min( $credit->credited, $self->owed ) ),
      };

    } else {
      die "guru meditation #12 and 35";
    }

    $app->invnum( $self->invnum );

    my $error = $app->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "Error inserting ". $app->table. " record: $error";
    }
    die $error if $error;

  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  ''; #no error

}

=item generate_email PARAMHASH

PARAMHASH can contain the following:

=over 4

=item from       => sender address, required

=item tempate    => alternate template name, optional

=item print_text => text attachment arrayref, optional

=item subject    => email subject, optional

=back

Returns an argument list to be passed to L<FS::Misc::send_email>.

=cut

use MIME::Entity;

sub generate_email {

  my $self = shift;
  my %args = @_;

  my $me = '[FS::cust_bill::generate_email]';

  my %return = (
    'from'      => $args{'from'},
    'subject'   => (($args{'subject'}) ? $args{'subject'} : 'Invoice'),
  );

  if (ref($args{'to'}) eq 'ARRAY') {
    $return{'to'} = $args{'to'};
  } else {
    $return{'to'} = [ grep { $_ !~ /^(POST|FAX)$/ }
                           $self->cust_main->invoicing_list
                    ];
  }

  if ( $conf->exists('invoice_html') ) {

    warn "$me creating HTML/text multipart message"
      if $DEBUG;

    $return{'nobody'} = 1;

    my $alternative = build MIME::Entity
      'Type'        => 'multipart/alternative',
      'Encoding'    => '7bit',
      'Disposition' => 'inline'
    ;

    my $data;
    if ( $conf->exists('invoice_email_pdf')
         and scalar($conf->config('invoice_email_pdf_note')) ) {

      warn "$me using 'invoice_email_pdf_note' in multipart message"
        if $DEBUG;
      $data = [ map { $_ . "\n" }
                    $conf->config('invoice_email_pdf_note')
              ];

    } else {

      warn "$me not using 'invoice_email_pdf_note' in multipart message"
        if $DEBUG;
      if ( ref($args{'print_text'}) eq 'ARRAY' ) {
        $data = $args{'print_text'};
      } else {
        $data = [ $self->print_text('', $args{'template'}) ];
      }

    }

    $alternative->attach(
      'Type'        => 'text/plain',
      #'Encoding'    => 'quoted-printable',
      'Encoding'    => '7bit',
      'Data'        => $data,
      'Disposition' => 'inline',
    );

    $args{'from'} =~ /\@([\w\.\-]+)/;
    my $from = $1 || 'example.com';
    my $content_id = join('.', rand()*(2**32), $$, time). "\@$from";

    my $path = "$FS::UID::conf_dir/conf.$FS::UID::datasrc";
    my $file;
    if ( defined($args{'template'}) && length($args{'template'})
         && -e "$path/logo_". $args{'template'}. ".png"
       )
    {
      $file = "$path/logo_". $args{'template'}. ".png";
    } else {
      $file = "$path/logo.png";
    }

    my $image = build MIME::Entity
      'Type'       => 'image/png',
      'Encoding'   => 'base64',
      'Path'       => $file,
      'Filename'   => 'logo.png',
      'Content-ID' => "<$content_id>",
    ;

    $alternative->attach(
      'Type'        => 'text/html',
      'Encoding'    => 'quoted-printable',
      'Data'        => [ '<html>',
                         '  <head>',
                         '    <title>',
                         '      '. encode_entities($return{'subject'}), 
                         '    </title>',
                         '  </head>',
                         '  <body bgcolor="#e8e8e8">',
                         $self->print_html('', $args{'template'}, $content_id),
                         '  </body>',
                         '</html>',
                       ],
      'Disposition' => 'inline',
      #'Filename'    => 'invoice.pdf',
    );

    if ( $conf->exists('invoice_email_pdf') ) {

      #attaching pdf too:
      # multipart/mixed
      #   multipart/related
      #     multipart/alternative
      #       text/plain
      #       text/html
      #     image/png
      #   application/pdf

      my $related = build MIME::Entity 'Type'     => 'multipart/related',
                                       'Encoding' => '7bit';

      #false laziness w/Misc::send_email
      $related->head->replace('Content-type',
        $related->mime_type.
        '; boundary="'. $related->head->multipart_boundary. '"'.
        '; type=multipart/alternative'
      );

      $related->add_part($alternative);

      $related->add_part($image);

      my $pdf = build MIME::Entity $self->mimebuild_pdf('', $args{'template'});

      $return{'mimeparts'} = [ $related, $pdf ];

    } else {

      #no other attachment:
      # multipart/related
      #   multipart/alternative
      #     text/plain
      #     text/html
      #   image/png

      $return{'content-type'} = 'multipart/related';
      $return{'mimeparts'} = [ $alternative, $image ];
      $return{'type'} = 'multipart/alternative'; #Content-Type of first part...
      #$return{'disposition'} = 'inline';

    }
  
  } else {

    if ( $conf->exists('invoice_email_pdf') ) {
      warn "$me creating PDF attachment"
        if $DEBUG;

      #mime parts arguments a la MIME::Entity->build().
      $return{'mimeparts'} = [
        { $self->mimebuild_pdf('', $args{'template'}) }
      ];
    }
  
    if ( $conf->exists('invoice_email_pdf')
         and scalar($conf->config('invoice_email_pdf_note')) ) {

      warn "$me using 'invoice_email_pdf_note'"
        if $DEBUG;
      $return{'body'} = [ map { $_ . "\n" }
                              $conf->config('invoice_email_pdf_note')
                        ];

    } else {

      warn "$me not using 'invoice_email_pdf_note'"
        if $DEBUG;
      if ( ref($args{'print_text'}) eq 'ARRAY' ) {
        $return{'body'} = $args{'print_text'};
      } else {
        $return{'body'} = [ $self->print_text('', $args{'template'}) ];
      }

    }

  }

  %return;

}

=item mimebuild_pdf

Returns a list suitable for passing to MIME::Entity->build(), representing
this invoice as PDF attachment.

=cut

sub mimebuild_pdf {
  my $self = shift;
  (
    'Type'        => 'application/pdf',
    'Encoding'    => 'base64',
    'Data'        => [ $self->print_pdf(@_) ],
    'Disposition' => 'attachment',
    'Filename'    => 'invoice.pdf',
  );
}

=item send [ TEMPLATENAME [ , AGENTNUM [ , INVOICE_FROM ] ] ]

Sends this invoice to the destinations configured for this customer: sends
email, prints and/or faxes.  See L<FS::cust_main_invoice>.

TEMPLATENAME, if specified, is the name of a suffix for alternate invoices.

AGENTNUM, if specified, means that this invoice will only be sent for customers
of the specified agent or agent(s).  AGENTNUM can be a scalar agentnum (for a
single agent) or an arrayref of agentnums.

INVOICE_FROM, if specified, overrides the default email invoice From: address.

AMOUNT, if specified, only sends the invoice if the total amount owed on this
invoice and all older invoices is greater than the specified amount.

=cut

sub queueable_send {
  my %opt = @_;

  my $self = qsearchs('cust_bill', { 'invnum' => $opt{invnum} } )
    or die "invalid invoice number: " . $opt{invnum};

  my @args = ( $opt{template}, $opt{agentnum} );
  push @args, $opt{invoice_from}
    if exists($opt{invoice_from}) && $opt{invoice_from};

  my $error = $self->send( @args );
  die $error if $error;

}

sub send {
  my $self = shift;
  my $template = scalar(@_) ? shift : '';
  if ( scalar(@_) && $_[0]  ) {
    my $agentnums = ref($_[0]) ? shift : [ shift ];
    return 'N/A' unless grep { $_ == $self->cust_main->agentnum } @$agentnums;
  }

  my $invoice_from =
    scalar(@_)
      ? shift
      : ( $self->_agent_invoice_from || $conf->config('invoice_from') );

  my $balance_over = ( scalar(@_) && $_[0] !~ /^\s*$/ ) ? shift : 0;

  return ''
    unless $self->cust_main->total_owed_date($self->_date) > $balance_over;

  my @invoicing_list = $self->cust_main->invoicing_list;

  #$self->email_invoice($template, $invoice_from)
  $self->email($template, $invoice_from)
    if grep { $_ !~ /^(POST|FAX)$/ } @invoicing_list or !@invoicing_list;

  #$self->print_invoice($template)
  $self->print($template)
    if grep { $_ eq 'POST' } @invoicing_list; #postal

  $self->fax_invoice($template)
    if grep { $_ eq 'FAX' } @invoicing_list; #fax

  '';

}

=item email [ TEMPLATENAME  [ , INVOICE_FROM ] ] 

Emails this invoice.

TEMPLATENAME, if specified, is the name of a suffix for alternate invoices.

INVOICE_FROM, if specified, overrides the default email invoice From: address.

=cut

sub queueable_email {
  my %opt = @_;

  my $self = qsearchs('cust_bill', { 'invnum' => $opt{invnum} } )
    or die "invalid invoice number: " . $opt{invnum};

  my @args = ( $opt{template} );
  push @args, $opt{invoice_from}
    if exists($opt{invoice_from}) && $opt{invoice_from};

  my $error = $self->email( @args );
  die $error if $error;

}

#sub email_invoice {
sub email {
  my $self = shift;
  my $template = scalar(@_) ? shift : '';
  my $invoice_from =
    scalar(@_)
      ? shift
      : ( $self->_agent_invoice_from || $conf->config('invoice_from') );

  my @invoicing_list = grep { $_ !~ /^(POST|FAX)$/ } 
                            $self->cust_main->invoicing_list;

  #better to notify this person than silence
  @invoicing_list = ($invoice_from) unless @invoicing_list;

  my $error = send_email(
    $self->generate_email(
      'from'       => $invoice_from,
      'to'         => [ grep { $_ !~ /^(POST|FAX)$/ } @invoicing_list ],
      'template'   => $template,
    )
  );
  die "can't email invoice: $error\n" if $error;
  #die "$error\n" if $error;

}

=item lpr_data [ TEMPLATENAME ]

Returns the postscript or plaintext for this invoice as an arrayref.

TEMPLATENAME, if specified, is the name of a suffix for alternate invoices.

=cut

sub lpr_data {
  my( $self, $template) = @_;
  $conf->exists('invoice_latex')
    ? [ $self->print_ps('', $template) ]
    : [ $self->print_text('', $template) ];
}

=item print [ TEMPLATENAME ]

Prints this invoice.

TEMPLATENAME, if specified, is the name of a suffix for alternate invoices.

=cut

#sub print_invoice {
sub print {
  my $self = shift;
  my $template = scalar(@_) ? shift : '';

  do_print $self->lpr_data($template);
}

=item fax_invoice [ TEMPLATENAME ] 

Faxes this invoice.

TEMPLATENAME, if specified, is the name of a suffix for alternate invoices.

=cut

sub fax_invoice {
  my $self = shift;
  my $template = scalar(@_) ? shift : '';

  die 'FAX invoice destination not (yet?) supported with plain text invoices.'
    unless $conf->exists('invoice_latex');

  my $dialstring = $self->cust_main->getfield('fax');
  #Check $dialstring?

  my $error = send_fax( 'docdata'    => $self->lpr_data($template),
                        'dialstring' => $dialstring,
                      );
  die $error if $error;

}

=item ftp_invoice [ TEMPLATENAME ] 

Sends this invoice data via FTP.

TEMPLATENAME is unused?

=cut

sub ftp_invoice {
  my $self = shift;
  my $template = scalar(@_) ? shift : '';

  $self->send_csv(
    'protocol'   => 'ftp',
    'server'     => $conf->config('cust_bill-ftpserver'),
    'username'   => $conf->config('cust_bill-ftpusername'),
    'password'   => $conf->config('cust_bill-ftppassword'),
    'dir'        => $conf->config('cust_bill-ftpdir'),
    'format'     => $conf->config('cust_bill-ftpformat'),
  );
}

=item spool_invoice [ TEMPLATENAME ] 

Spools this invoice data (see L<FS::spool_csv>)

TEMPLATENAME is unused?

=cut

sub spool_invoice {
  my $self = shift;
  my $template = scalar(@_) ? shift : '';

  $self->spool_csv(
    'format'       => $conf->config('cust_bill-spoolformat'),
    'agent_spools' => $conf->exists('cust_bill-spoolagent'),
  );
}

=item send_if_newest [ TEMPLATENAME [ , AGENTNUM [ , INVOICE_FROM ] ] ]

Like B<send>, but only sends the invoice if it is the newest open invoice for
this customer.

=cut

sub send_if_newest {
  my $self = shift;

  return ''
    if scalar(
               grep { $_->owed > 0 } 
                    qsearch('cust_bill', {
                      'custnum' => $self->custnum,
                      #'_date'   => { op=>'>', value=>$self->_date },
                      'invnum'  => { op=>'>', value=>$self->invnum },
                    } )
             );
    
  $self->send(@_);
}

=item send_csv OPTION => VALUE, ...

Sends invoice as a CSV data-file to a remote host with the specified protocol.

Options are:

protocol - currently only "ftp"
server
username
password
dir

The file will be named "N-YYYYMMDDHHMMSS.csv" where N is the invoice number
and YYMMDDHHMMSS is a timestamp.

See L</print_csv> for a description of the output format.

=cut

sub send_csv {
  my($self, %opt) = @_;

  #create file(s)

  my $spooldir = "/usr/local/etc/freeside/export.". datasrc. "/cust_bill";
  mkdir $spooldir, 0700 unless -d $spooldir;

  my $tracctnum = $self->invnum. time2str('-%Y%m%d%H%M%S', time);
  my $file = "$spooldir/$tracctnum.csv";
  
  my ( $header, $detail ) = $self->print_csv(%opt, 'tracctnum' => $tracctnum );

  open(CSV, ">$file") or die "can't open $file: $!";
  print CSV $header;

  print CSV $detail;

  close CSV;

  my $net;
  if ( $opt{protocol} eq 'ftp' ) {
    eval "use Net::FTP;";
    die $@ if $@;
    $net = Net::FTP->new($opt{server}) or die @$;
  } else {
    die "unknown protocol: $opt{protocol}";
  }

  $net->login( $opt{username}, $opt{password} )
    or die "can't FTP to $opt{username}\@$opt{server}: login error: $@";

  $net->binary or die "can't set binary mode";

  $net->cwd($opt{dir}) or die "can't cwd to $opt{dir}";

  $net->put($file) or die "can't put $file: $!";

  $net->quit;

  unlink $file;

}

=item spool_csv

Spools CSV invoice data.

Options are:

=over 4

=item format - 'default' or 'billco'

=item dest - if set (to POST, EMAIL or FAX), only sends spools invoices if the customer has the corresponding invoice destinations set (see L<FS::cust_main_invoice>).

=item agent_spools - if set to a true value, will spool to per-agent files rather than a single global file

=item balanceover - if set, only spools the invoice if the total amount owed on this invoice and all older invoices is greater than the specified amount.

=back

=cut

sub spool_csv {
  my($self, %opt) = @_;

  my $cust_main = $self->cust_main;

  if ( $opt{'dest'} ) {
    my %invoicing_list = map { /^(POST|FAX)$/ or 'EMAIL' =~ /^(.*)$/; $1 => 1 }
                             $cust_main->invoicing_list;
    return 'N/A' unless $invoicing_list{$opt{'dest'}}
                     || ! keys %invoicing_list;
  }

  if ( $opt{'balanceover'} ) {
    return 'N/A'
      if $cust_main->total_owed_date($self->_date) < $opt{'balanceover'};
  }

  my $spooldir = "/usr/local/etc/freeside/export.". datasrc. "/cust_bill";
  mkdir $spooldir, 0700 unless -d $spooldir;

  my $tracctnum = $self->invnum. time2str('-%Y%m%d%H%M%S', time);

  my $file =
    "$spooldir/".
    ( $opt{'agent_spools'} ? 'agentnum'.$cust_main->agentnum : 'spool' ).
    ( lc($opt{'format'}) eq 'billco' ? '-header' : '' ) .
    '.csv';
  
  my ( $header, $detail ) = $self->print_csv(%opt, 'tracctnum' => $tracctnum );

  open(CSV, ">>$file") or die "can't open $file: $!";
  flock(CSV, LOCK_EX);
  seek(CSV, 0, 2);

  print CSV $header;

  if ( lc($opt{'format'}) eq 'billco' ) {

    flock(CSV, LOCK_UN);
    close CSV;

    $file =
      "$spooldir/".
      ( $opt{'agent_spools'} ? 'agentnum'.$cust_main->agentnum : 'spool' ).
      '-detail.csv';

    open(CSV,">>$file") or die "can't open $file: $!";
    flock(CSV, LOCK_EX);
    seek(CSV, 0, 2);
  }

  print CSV $detail;

  flock(CSV, LOCK_UN);
  close CSV;

  return '';

}

=item print_csv OPTION => VALUE, ...

Returns CSV data for this invoice.

Options are:

format - 'default' or 'billco'

Returns a list consisting of two scalars.  The first is a single line of CSV
header information for this invoice.  The second is one or more lines of CSV
detail information for this invoice.

If I<format> is not specified or "default", the fields of the CSV file are as
follows:

record_type, invnum, custnum, _date, charged, first, last, company, address1, address2, city, state, zip, country, pkg, setup, recur, sdate, edate

=over 4

=item record type - B<record_type> is either C<cust_bill> or C<cust_bill_pkg>

B<record_type> is C<cust_bill> for the initial header line only.  The
last five fields (B<pkg> through B<edate>) are irrelevant, and all other
fields are filled in.

B<record_type> is C<cust_bill_pkg> for detail lines.  Only the first two fields
(B<record_type> and B<invnum>) and the last five fields (B<pkg> through B<edate>)
are filled in.

=item invnum - invoice number

=item custnum - customer number

=item _date - invoice date

=item charged - total invoice amount

=item first - customer first name

=item last - customer first name

=item company - company name

=item address1 - address line 1

=item address2 - address line 1

=item city

=item state

=item zip

=item country

=item pkg - line item description

=item setup - line item setup fee (one or both of B<setup> and B<recur> will be defined)

=item recur - line item recurring fee (one or both of B<setup> and B<recur> will be defined)

=item sdate - start date for recurring fee

=item edate - end date for recurring fee

=back

If I<format> is "billco", the fields of the header CSV file are as follows:

  +-------------------------------------------------------------------+
  |                        FORMAT HEADER FILE                         |
  |-------------------------------------------------------------------|
  | Field | Description                   | Name       | Type | Width |
  | 1     | N/A-Leave Empty               | RC         | CHAR |     2 |
  | 2     | N/A-Leave Empty               | CUSTID     | CHAR |    15 |
  | 3     | Transaction Account No        | TRACCTNUM  | CHAR |    15 |
  | 4     | Transaction Invoice No        | TRINVOICE  | CHAR |    15 |
  | 5     | Transaction Zip Code          | TRZIP      | CHAR |     5 |
  | 6     | Transaction Company Bill To   | TRCOMPANY  | CHAR |    30 |
  | 7     | Transaction Contact Bill To   | TRNAME     | CHAR |    30 |
  | 8     | Additional Address Unit Info  | TRADDR1    | CHAR |    30 |
  | 9     | Bill To Street Address        | TRADDR2    | CHAR |    30 |
  | 10    | Ancillary Billing Information | TRADDR3    | CHAR |    30 |
  | 11    | Transaction City Bill To      | TRCITY     | CHAR |    20 |
  | 12    | Transaction State Bill To     | TRSTATE    | CHAR |     2 |
  | 13    | Bill Cycle Close Date         | CLOSEDATE  | CHAR |    10 |
  | 14    | Bill Due Date                 | DUEDATE    | CHAR |    10 |
  | 15    | Previous Balance              | BALFWD     | NUM* |     9 |
  | 16    | Pmt/CR Applied                | CREDAPPLY  | NUM* |     9 |
  | 17    | Total Current Charges         | CURRENTCHG | NUM* |     9 |
  | 18    | Total Amt Due                 | TOTALDUE   | NUM* |     9 |
  | 19    | Total Amt Due                 | AMTDUE     | NUM* |     9 |
  | 20    | 30 Day Aging                  | AMT30      | NUM* |     9 |
  | 21    | 60 Day Aging                  | AMT60      | NUM* |     9 |
  | 22    | 90 Day Aging                  | AMT90      | NUM* |     9 |
  | 23    | Y/N                           | AGESWITCH  | CHAR |     1 |
  | 24    | Remittance automation         | SCANLINE   | CHAR |   100 |
  | 25    | Total Taxes & Fees            | TAXTOT     | NUM* |     9 |
  | 26    | Customer Reference Number     | CUSTREF    | CHAR |    15 |
  | 27    | Federal Tax***                | FEDTAX     | NUM* |     9 |
  | 28    | State Tax***                  | STATETAX   | NUM* |     9 |
  | 29    | Other Taxes & Fees***         | OTHERTAX   | NUM* |     9 |
  +-------+-------------------------------+------------+------+-------+

If I<format> is "billco", the fields of the detail CSV file are as follows:

                                  FORMAT FOR DETAIL FILE
        |                            |           |      |
  Field | Description                | Name      | Type | Width
  1     | N/A-Leave Empty            | RC        | CHAR |     2
  2     | N/A-Leave Empty            | CUSTID    | CHAR |    15
  3     | Account Number             | TRACCTNUM | CHAR |    15
  4     | Invoice Number             | TRINVOICE | CHAR |    15
  5     | Line Sequence (sort order) | LINESEQ   | NUM  |     6
  6     | Transaction Detail         | DETAILS   | CHAR |   100
  7     | Amount                     | AMT       | NUM* |     9
  8     | Line Format Control**      | LNCTRL    | CHAR |     2
  9     | Grouping Code              | GROUP     | CHAR |     2
  10    | User Defined               | ACCT CODE | CHAR |    15

=cut

sub print_csv {
  my($self, %opt) = @_;
  
  eval "use Text::CSV_XS";
  die $@ if $@;

  my $cust_main = $self->cust_main;

  my $csv = Text::CSV_XS->new({'always_quote'=>1});

  if ( lc($opt{'format'}) eq 'billco' ) {

    my $taxtotal = 0;
    $taxtotal += $_->{'amount'} foreach $self->_items_tax;

    my $duedate = $self->balance_due_date;

    my( $previous_balance, @unused ) = $self->previous; #previous balance

    my $pmt_cr_applied = 0;
    $pmt_cr_applied += $_->{'amount'}
      foreach ( $self->_items_payments, $self->_items_credits ) ;

    my $totaldue = sprintf('%.2f', $self->owed + $previous_balance);

    $csv->combine(
      '',                         #  1 | N/A-Leave Empty               CHAR   2
      '',                         #  2 | N/A-Leave Empty               CHAR  15
      $opt{'tracctnum'},          #  3 | Transaction Account No        CHAR  15
      $self->invnum,              #  4 | Transaction Invoice No        CHAR  15
      $cust_main->zip,            #  5 | Transaction Zip Code          CHAR   5
      $cust_main->company,        #  6 | Transaction Company Bill To   CHAR  30
      #$cust_main->payname,        #  7 | Transaction Contact Bill To   CHAR  30
      $cust_main->contact,        #  7 | Transaction Contact Bill To   CHAR  30
      $cust_main->address2,       #  8 | Additional Address Unit Info  CHAR  30
      $cust_main->address1,       #  9 | Bill To Street Address        CHAR  30
      '',                         # 10 | Ancillary Billing Information CHAR  30
      $cust_main->city,           # 11 | Transaction City Bill To      CHAR  20
      $cust_main->state,          # 12 | Transaction State Bill To     CHAR   2

      # XXX ?
      time2str("%m/%d/%Y", $self->_date), # 13 | Bill Cycle Close Date CHAR  10

      # XXX ?
      $duedate,                   # 14 | Bill Due Date                 CHAR  10

      $previous_balance,          # 15 | Previous Balance              NUM*   9
      $pmt_cr_applied,            # 16 | Pmt/CR Applied                NUM*   9
      sprintf("%.2f", $self->charged), # 17 | Total Current Charges    NUM*   9
      $totaldue,                  # 18 | Total Amt Due                 NUM*   9
      $totaldue,                  # 19 | Total Amt Due                 NUM*   9
      '',                         # 20 | 30 Day Aging                  NUM*   9
      '',                         # 21 | 60 Day Aging                  NUM*   9
      '',                         # 22 | 90 Day Aging                  NUM*   9
      'N',                        # 23 | Y/N                           CHAR   1
      '',                         # 24 | Remittance automation         CHAR 100
      $taxtotal,                  # 25 | Total Taxes & Fees            NUM*   9
      $self->custnum,             # 26 | Customer Reference Number     CHAR  15
      '0',                        # 27 | Federal Tax***                NUM*   9
      sprintf("%.2f", $taxtotal), # 28 | State Tax***                  NUM*   9
      '0',                        # 29 | Other Taxes & Fees***         NUM*   9
    );

  } else {
  
    $csv->combine(
      'cust_bill',
      $self->invnum,
      $self->custnum,
      time2str("%x", $self->_date),
      sprintf("%.2f", $self->charged),
      ( map { $cust_main->getfield($_) }
          qw( first last company address1 address2 city state zip country ) ),
      map { '' } (1..5),
    ) or die "can't create csv";
  }

  my $header = $csv->string. "\n";

  my $detail = '';
  if ( lc($opt{'format'}) eq 'billco' ) {

    my $lineseq = 0;
    foreach my $item ( $self->_items_pkg ) {

      $csv->combine(
        '',                     #  1 | N/A-Leave Empty            CHAR   2
        '',                     #  2 | N/A-Leave Empty            CHAR  15
        $opt{'tracctnum'},      #  3 | Account Number             CHAR  15
        $self->invnum,          #  4 | Invoice Number             CHAR  15
        $lineseq++,             #  5 | Line Sequence (sort order) NUM    6
        $item->{'description'}, #  6 | Transaction Detail         CHAR 100
        $item->{'amount'},      #  7 | Amount                     NUM*   9
        '',                     #  8 | Line Format Control**      CHAR   2
        '',                     #  9 | Grouping Code              CHAR   2
        '',                     # 10 | User Defined               CHAR  15
      );

      $detail .= $csv->string. "\n";

    }

  } else {

    foreach my $cust_bill_pkg ( $self->cust_bill_pkg ) {

      my($pkg, $setup, $recur, $sdate, $edate);
      if ( $cust_bill_pkg->pkgnum ) {
      
        ($pkg, $setup, $recur, $sdate, $edate) = (
          $cust_bill_pkg->cust_pkg->part_pkg->pkg,
          ( $cust_bill_pkg->setup != 0
            ? sprintf("%.2f", $cust_bill_pkg->setup )
            : '' ),
          ( $cust_bill_pkg->recur != 0
            ? sprintf("%.2f", $cust_bill_pkg->recur )
            : '' ),
          ( $cust_bill_pkg->sdate 
            ? time2str("%x", $cust_bill_pkg->sdate)
            : '' ),
          ($cust_bill_pkg->edate 
            ?time2str("%x", $cust_bill_pkg->edate)
            : '' ),
        );
  
      } else { #pkgnum tax
        next unless $cust_bill_pkg->setup != 0;
        my $itemdesc = defined $cust_bill_pkg->dbdef_table->column('itemdesc')
                         ? ( $cust_bill_pkg->itemdesc || 'Tax' )
                         : 'Tax';
        ($pkg, $setup, $recur, $sdate, $edate) =
          ( $itemdesc, sprintf("%10.2f",$cust_bill_pkg->setup), '', '', '' );
      }
  
      $csv->combine(
        'cust_bill_pkg',
        $self->invnum,
        ( map { '' } (1..11) ),
        ($pkg, $setup, $recur, $sdate, $edate)
      ) or die "can't create csv";

      $detail .= $csv->string. "\n";

    }

  }

  ( $header, $detail );

}

=item comp

Pays this invoice with a compliemntary payment.  If there is an error,
returns the error, otherwise returns false.

=cut

sub comp {
  my $self = shift;
  my $cust_pay = new FS::cust_pay ( {
    'invnum'   => $self->invnum,
    'paid'     => $self->owed,
    '_date'    => '',
    'payby'    => 'COMP',
    'payinfo'  => $self->cust_main->payinfo,
    'paybatch' => '',
  } );
  $cust_pay->insert;
}

=item realtime_card

Attempts to pay this invoice with a credit card payment via a
Business::OnlinePayment realtime gateway.  See
http://search.cpan.org/search?mode=module&query=Business%3A%3AOnlinePayment
for supported processors.

=cut

sub realtime_card {
  my $self = shift;
  $self->realtime_bop( 'CC', @_ );
}

=item realtime_ach

Attempts to pay this invoice with an electronic check (ACH) payment via a
Business::OnlinePayment realtime gateway.  See
http://search.cpan.org/search?mode=module&query=Business%3A%3AOnlinePayment
for supported processors.

=cut

sub realtime_ach {
  my $self = shift;
  $self->realtime_bop( 'ECHECK', @_ );
}

=item realtime_lec

Attempts to pay this invoice with phone bill (LEC) payment via a
Business::OnlinePayment realtime gateway.  See
http://search.cpan.org/search?mode=module&query=Business%3A%3AOnlinePayment
for supported processors.

=cut

sub realtime_lec {
  my $self = shift;
  $self->realtime_bop( 'LEC', @_ );
}

sub realtime_bop {
  my( $self, $method ) = @_;

  my $cust_main = $self->cust_main;
  my $balance = $cust_main->balance;
  my $amount = ( $balance < $self->owed ) ? $balance : $self->owed;
  $amount = sprintf("%.2f", $amount);
  return "not run (balance $balance)" unless $amount > 0;

  my $description = 'Internet Services';
  if ( $conf->exists('business-onlinepayment-description') ) {
    my $dtempl = $conf->config('business-onlinepayment-description');

    my $agent_obj = $cust_main->agent
      or die "can't retreive agent for $cust_main (agentnum ".
             $cust_main->agentnum. ")";
    my $agent = $agent_obj->agent;
    my $pkgs = join(', ',
      map { $_->cust_pkg->part_pkg->pkg }
        grep { $_->pkgnum } $self->cust_bill_pkg
    );
    $description = eval qq("$dtempl");
  }

  $cust_main->realtime_bop($method, $amount,
    'description' => $description,
    'invnum'      => $self->invnum,
  );

}

=item batch_card OPTION => VALUE...

Adds a payment for this invoice to the pending credit card batch (see
L<FS::cust_pay_batch>), or, if the B<realtime> option is set to a true value,
runs the payment using a realtime gateway.

=cut

sub batch_card {
  my ($self, %options) = @_;
  my $cust_main = $self->cust_main;

  $options{invnum} = $self->invnum;
  
  $cust_main->batch_card(%options);
}

sub _agent_template {
  my $self = shift;
  $self->cust_main->agent_template;
}

sub _agent_invoice_from {
  my $self = shift;
  $self->cust_main->agent_invoice_from;
}

=item print_text [ TIME [ , TEMPLATE ] ]

Returns an text invoice, as a list of lines.

TIME an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=cut

#still some false laziness w/_items stuff (and send_csv)
sub print_text {

  my( $self, $today, $template ) = @_;
  $today ||= time;

#  my $invnum = $self->invnum;
  my $cust_main = $self->cust_main;
  $cust_main->payname( $cust_main->first. ' '. $cust_main->getfield('last') )
    unless $cust_main->payname && $cust_main->payby !~ /^(CHEK|DCHK)$/;

  my( $pr_total, @pr_cust_bill ) = $self->previous; #previous balance
#  my( $cr_total, @cr_cust_credit ) = $self->cust_credit; #credits
  #my $balance_due = $self->owed + $pr_total - $cr_total;
  my $balance_due = $self->owed + $pr_total;

  #my @collect = ();
  #my($description,$amount);
  @buf = ();

  #previous balance
  unless ($conf->exists('disable_previous_balance')) {
    foreach ( @pr_cust_bill ) {
      push @buf, [
        "Previous Balance, Invoice #". $_->invnum. 
                   " (". time2str("%x",$_->_date). ")",
        $money_char. sprintf("%10.2f",$_->owed)
      ];
    }
    if (@pr_cust_bill) {
      push @buf,['','-----------'];
      push @buf,[ 'Total Previous Balance',
                  $money_char. sprintf("%10.2f",$pr_total ) ];
      push @buf,['',''];
    }
  }

  #new charges
  foreach my $cust_bill_pkg (
    ( grep {   $_->pkgnum } $self->cust_bill_pkg ),  #packages first
    ( grep { ! $_->pkgnum } $self->cust_bill_pkg ),  #then taxes
  ) {

    my $desc = $cust_bill_pkg->desc;

    if ( $cust_bill_pkg->pkgnum > 0 ) {

      if ( $cust_bill_pkg->setup != 0 ) {
        my $description = $desc;
        $description .= ' Setup' if $cust_bill_pkg->recur != 0;
        push @buf, [ $description,
                     $money_char. sprintf("%10.2f", $cust_bill_pkg->setup) ];
        push @buf,
          map { [ "  ". $_->[0]. ": ". $_->[1], '' ] }
              $cust_bill_pkg->cust_pkg->h_labels($self->_date);
      }

      if ( $cust_bill_pkg->recur != 0 ) {
        push @buf, [
          $desc .
            ( $conf->exists('disable_line_item_date_ranges')
              ? ''
              : " (" . time2str("%x", $cust_bill_pkg->sdate) . " - " .
                       time2str("%x", $cust_bill_pkg->edate) . ")"
            ),
          $money_char. sprintf("%10.2f", $cust_bill_pkg->recur)
        ];
        push @buf,
          map { [ "  ". $_->[0]. ": ". $_->[1], '' ] }
              $cust_bill_pkg->cust_pkg->h_labels( $cust_bill_pkg->edate,
                                                  $cust_bill_pkg->sdate );
      }

      push @buf, map { [ "  $_", '' ] } $cust_bill_pkg->details;

    } else { #pkgnum tax or one-shot line item

      if ( $cust_bill_pkg->setup != 0 ) {
        push @buf, [ $desc,
                     $money_char. sprintf("%10.2f", $cust_bill_pkg->setup) ];
      }
      if ( $cust_bill_pkg->recur != 0 ) {
        push @buf, [ "$desc (". time2str("%x", $cust_bill_pkg->sdate). " - "
                              . time2str("%x", $cust_bill_pkg->edate). ")",
                     $money_char. sprintf("%10.2f", $cust_bill_pkg->recur)
                   ];
      }

    }

  }

  push @buf,['','-----------'];
  push @buf,[ ( $conf->exists('disable_previous_balance')
                ? 'Total Charges'
                : 'Total New Charges'),
             $money_char. sprintf("%10.2f",$self->charged) ];
  push @buf,['',''];

  unless ($conf->exists('disable_previous_balance')) {
    push @buf,['','-----------'];
    push @buf,['Total Charges',
               $money_char. sprintf("%10.2f",$self->charged + $pr_total) ];
    push @buf,['',''];

    #credits
    foreach ( $self->cust_credited ) {

      #something more elaborate if $_->amount ne $_->cust_credit->credited ?

      my $reason = substr($_->cust_credit->reason,0,32);
      $reason .= '...' if length($reason) < length($_->cust_credit->reason);
      $reason = " ($reason) " if $reason;
      push @buf,[
        "Credit #". $_->crednum. " (". time2str("%x",$_->cust_credit->_date) .")".
          $reason,
        $money_char. sprintf("%10.2f",$_->amount)
      ];
    }
    #foreach ( @cr_cust_credit ) {
    #  push @buf,[
    #    "Credit #". $_->crednum. " (" . time2str("%x",$_->_date) .")",
    #    $money_char. sprintf("%10.2f",$_->credited)
    #  ];
    #}

    #get & print payments
    foreach ( $self->cust_bill_pay ) {

      #something more elaborate if $_->amount ne ->cust_pay->paid ?

      push @buf,[
        "Payment received ". time2str("%x",$_->cust_pay->_date ),
        $money_char. sprintf("%10.2f",$_->amount )
      ];
    }

    #balance due
    my $balance_due_msg = $self->balance_due_msg;

    push @buf,['','-----------'];
    push @buf,[$balance_due_msg, $money_char. 
      sprintf("%10.2f", $balance_due ) ];
  }

  #create the template
  $template ||= $self->_agent_template;
  my $templatefile = 'invoice_template';
  $templatefile .= "_$template" if length($template);
  my @invoice_template = $conf->config($templatefile)
    or die "cannot load config file $templatefile";
  $invoice_lines = 0;
  my $wasfunc = 0;
  foreach ( grep /invoice_lines\(\d*\)/, @invoice_template ) { #kludgy
    /invoice_lines\((\d*)\)/;
    $invoice_lines += $1 || scalar(@buf);
    $wasfunc=1;
  }
  die "no invoice_lines() functions in template?" unless $wasfunc;
  my $invoice_template = new Text::Template (
    TYPE   => 'ARRAY',
    SOURCE => [ map "$_\n", @invoice_template ],
  ) or die "can't create new Text::Template object: $Text::Template::ERROR";
  $invoice_template->compile()
    or die "can't compile template: $Text::Template::ERROR";

  #setup template variables
  package FS::cust_bill::_template; #!
  use vars qw( $custnum $invnum $date $agent @address $overdue
               $page $total_pages @buf );

  $custnum = $self->custnum;
  $invnum = $self->invnum;
  $date = $self->_date;
  $agent = $self->cust_main->agent->agent;
  $page = 1;

  if ( $FS::cust_bill::invoice_lines ) {
    $total_pages =
      int( scalar(@FS::cust_bill::buf) / $FS::cust_bill::invoice_lines );
    $total_pages++
      if scalar(@FS::cust_bill::buf) % $FS::cust_bill::invoice_lines;
  } else {
    $total_pages = 1;
  }

  #format address (variable for the template)
  my $l = 0;
  @address = ( '', '', '', '', '', '' );
  package FS::cust_bill; #!
  $FS::cust_bill::_template::address[$l++] =
    $cust_main->payname.
      ( ( $cust_main->payby eq 'BILL' ) && $cust_main->payinfo
        ? " (P.O. #". $cust_main->payinfo. ")"
        : ''
      )
  ;
  $FS::cust_bill::_template::address[$l++] = $cust_main->company
    if $cust_main->company;
  $FS::cust_bill::_template::address[$l++] = $cust_main->address1;
  $FS::cust_bill::_template::address[$l++] = $cust_main->address2
    if $cust_main->address2;
  $FS::cust_bill::_template::address[$l++] =
    $cust_main->city. ", ". $cust_main->state. "  ".  $cust_main->zip;

  my $countrydefault = $conf->config('countrydefault') || 'US';
  $FS::cust_bill::_template::address[$l++] = code2country($cust_main->country)
    unless $cust_main->country eq $countrydefault;

	#  #overdue? (variable for the template)
	#  $FS::cust_bill::_template::overdue = ( 
	#    $balance_due > 0
	#    && $today > $self->_date 
	##    && $self->printed > 1
	#    && $self->printed > 0
	#  );

  #and subroutine for the template
  sub FS::cust_bill::_template::invoice_lines {
    my $lines = shift || scalar(@buf);
    map { 
      scalar(@buf) ? shift @buf : [ '', '' ];
    }
    ( 1 .. $lines );
  }

  #and fill it in
  $FS::cust_bill::_template::page = 1;
  my $lines;
  my @collect;
  while (@buf) {
    push @collect, split("\n",
      $invoice_template->fill_in( PACKAGE => 'FS::cust_bill::_template' )
    );
    $FS::cust_bill::_template::page++;
  }

  map "$_\n", @collect;

}

=item print_latex [ TIME [ , TEMPLATE ] ]

Internal method - returns a filename of a filled-in LaTeX template for this
invoice (Note: add ".tex" to get the actual filename).

See print_ps and print_pdf for methods that return PostScript and PDF output.

TIME an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=cut

#still some false laziness w/print_text and print_html (and send_csv) (mostly print_text should use _items stuff though)
sub print_latex {

  my( $self, $today, $template ) = @_;
  $today ||= time;
  warn "FS::cust_bill::print_latex called on $self with suffix $template\n"
    if $DEBUG;

  my $cust_main = $self->cust_main;
  $cust_main->payname( $cust_main->first. ' '. $cust_main->getfield('last') )
    unless $cust_main->payname && $cust_main->payby !~ /^(CHEK|DCHK)$/;

  my( $pr_total, @pr_cust_bill ) = $self->previous; #previous balance
#  my( $cr_total, @cr_cust_credit ) = $self->cust_credit; #credits
  #my $balance_due = $self->owed + $pr_total - $cr_total;
  my $balance_due = $self->owed + $pr_total;

  #create the template
  $template ||= $self->_agent_template;
  my $templatefile = 'invoice_latex';
  my $suffix = length($template) ? "_$template" : '';
  $templatefile .= $suffix;
  my @invoice_template = map "$_\n", $conf->config($templatefile)
    or die "cannot load config file $templatefile";

  my($format, $text_template);
  if ( grep { /^%%Detail/ } @invoice_template ) {
    #change this to a die when the old code is removed
    warn "old-style invoice template $templatefile; ".
         "patch with conf/invoice_latex.diff or use new conf/invoice_latex*\n";
    $format = 'old';
  } else {
    $format = 'Text::Template';
    $text_template = new Text::Template(
      TYPE => 'ARRAY',
      SOURCE => \@invoice_template,
      DELIMITERS => [ '[@--', '--@]' ],
    );

    $text_template->compile()
      or die 'While compiling ' . $templatefile . ': ' . $Text::Template::ERROR;
  }

  my $returnaddress;
  if ( length($conf->config_orbase('invoice_latexreturnaddress', $template)) ) {
    $returnaddress = join("\n",
      $conf->config_orbase('invoice_latexreturnaddress', $template)
    );
  } else {
    $returnaddress = '~';
  }

  my %invoice_data = (
    'custnum'      => $self->custnum,
    'invnum'       => $self->invnum,
    'date'         => time2str('%b %o, %Y', $self->_date),
    'today'        => time2str('%b %o, %Y', $today),
    'agent'        => _latex_escape($cust_main->agent->agent),
    'agent_custid' => _latex_escape($cust_main->agent_custid),
    'payname'      => _latex_escape($cust_main->payname),
    'company'      => _latex_escape($cust_main->company),
    'address1'     => _latex_escape($cust_main->address1),
    'address2'     => _latex_escape($cust_main->address2),
    'city'         => _latex_escape($cust_main->city),
    'state'        => _latex_escape($cust_main->state),
    #'quantity'     => 1,
    'zip'          => _latex_escape($cust_main->zip),
    'fax'          => _latex_escape($cust_main->fax),
    'footer'       => join("\n", $conf->config_orbase('invoice_latexfooter', $template) ),
    'smallfooter'  => join("\n", $conf->config_orbase('invoice_latexsmallfooter', $template) ),
    'returnaddress' => $returnaddress,
    'quantity'     => 1,
    'terms'        => $conf->config('invoice_default_terms') || 'Payable upon receipt',
    #'notes'        => join("\n", $conf->config('invoice_latexnotes') ),
    'conf_dir'     => "$FS::UID::conf_dir/conf.$FS::UID::datasrc",
    'current_charges'  => sprintf('%.2f', $self->charged ),
    'previous_balance' => sprintf("%.2f", $pr_total),
    'balance'      => sprintf("%.2f", $balance_due),
    'duedate'      => $self->balance_due_date,
    'ship_enable'  => $conf->exists('invoice-ship_address'),
    'unitprices'   => $conf->exists('invoice-unitprice'),
  );

  my $countrydefault = $conf->config('countrydefault') || 'US';
  my $prefix = $cust_main->has_ship_address ? 'ship_' : '';
  foreach ( qw( contact company address1 address2 city state zip country fax) ){
    my $method = $prefix.$_;
    $invoice_data{"ship_$_"} = _latex_escape($cust_main->$method);
  }
  $invoice_data{'ship_country'} = ''
    if ( $invoice_data{'ship_country'} eq $countrydefault );

  if ( $cust_main->country eq $countrydefault ) {
    $invoice_data{'country'} = '';
  } else {
    $invoice_data{'country'} = _latex_escape(code2country($cust_main->country));
  }

  $invoice_data{'notes'} =
    join("\n",
#  #do variable substitutions in notes
#      map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
        $conf->config_orbase('invoice_latexnotes', $template)
    );
  warn "invoice notes: ". $invoice_data{'notes'}. "\n"
    if $DEBUG;

  #do variable substitution in coupon
  foreach my $include (qw( coupon )) {

    my @inc_src = $conf->config_orbase("invoice_latex$include", $template);

    my $inc_tt = new Text::Template (
      TYPE       => 'ARRAY',
      SOURCE     => [ map "$_\n", @inc_src ],
      DELIMITERS => [ '[@--', '--@]' ],
    ) or die "Can't create new Text::Template object: $Text::Template::ERROR";

    unless ( $inc_tt->compile() ) {
      my $error = "Can't compile $include template: $Text::Template::ERROR\n";
      warn $error. "Template:\n". join('', map "$_\n", @inc_src);
      die $error;
    }

    $invoice_data{$include} = $inc_tt->fill_in( HASH => \%invoice_data );

    $invoice_data{$include} =~ s/\n+$//
  }

  $invoice_data{'footer'} =~ s/\n+$//;
  $invoice_data{'smallfooter'} =~ s/\n+$//;
  $invoice_data{'notes'} =~ s/\n+$//;

  $invoice_data{'po_line'} =
    (  $cust_main->payby eq 'BILL' && $cust_main->payinfo )
      ? _latex_escape("Purchase Order #". $cust_main->payinfo)
      : '~';

  my @filled_in = ();
  if ( $format eq 'old' ) {
  
    my @line_item = ();
    my @total_item = ();
    while ( @invoice_template ) {
      my $line = shift @invoice_template;
  
      if ( $line =~ /^%%Detail\s*$/ ) {
  
        while ( ( my $line_item_line = shift @invoice_template )
                !~ /^%%EndDetail\s*$/                            ) {
          push @line_item, $line_item_line;
        }
        foreach my $line_item ( $self->_items ) {
        #foreach my $line_item ( $self->_items_pkg ) {
          $invoice_data{'ref'} = $line_item->{'pkgnum'};
          $invoice_data{'description'} =
            _latex_escape($line_item->{'description'});
          if ( exists $line_item->{'ext_description'} ) {
            $invoice_data{'description'} .=
              "\\tabularnewline\n~~".
              join( "\\tabularnewline\n~~",
                    map _latex_escape($_), @{$line_item->{'ext_description'}}
                  );
          }
          $invoice_data{'amount'}       = $line_item->{'amount'};
          $invoice_data{'unit_amount'}  = $line_item->{'unit_amount'};
          $invoice_data{'quantity'}     = $line_item->{'quantity'};
          $invoice_data{'product_code'} = $line_item->{'pkgpart'} || 'N/A';
          push @filled_in,
            map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b } @line_item;
        }
  
      } elsif ( $line =~ /^%%TotalDetails\s*$/ ) {
  
        while ( ( my $total_item_line = shift @invoice_template )
                !~ /^%%EndTotalDetails\s*$/                      ) {
          push @total_item, $total_item_line;
        }
  
        my @total_fill = ();
  
        my $taxtotal = 0;
        foreach my $tax ( $self->_items_tax ) {
          $invoice_data{'total_item'} = _latex_escape($tax->{'description'});
          $taxtotal += $tax->{'amount'};
          $invoice_data{'total_amount'} = '\dollar '. $tax->{'amount'};
          push @total_fill,
            map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
                @total_item;
        }

        if ( $taxtotal ) {
          $invoice_data{'total_item'} = 'Sub-total';
          $invoice_data{'total_amount'} =
            '\dollar '. sprintf('%.2f', $self->charged - $taxtotal );
          unshift @total_fill,
            map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
                @total_item;
        }
  
        $invoice_data{'total_item'} = '\textbf{Total}';
        $invoice_data{'total_amount'} =
          '\textbf{\dollar '. sprintf('%.2f', $self->charged + $pr_total ). '}';
        push @total_fill,
          map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
              @total_item;
  
        #foreach my $thing ( sort { $a->_date <=> $b->_date } $self->_items_credits, $self->_items_payments
  
        # credits
        foreach my $credit ( $self->_items_credits ) {
          $invoice_data{'total_item'} = _latex_escape($credit->{'description'});
          #$credittotal
          $invoice_data{'total_amount'} = '-\dollar '. $credit->{'amount'};
          push @total_fill, 
            map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
                @total_item;
        }
  
        # payments
        foreach my $payment ( $self->_items_payments ) {
          $invoice_data{'total_item'} = _latex_escape($payment->{'description'});
          #$paymenttotal
          $invoice_data{'total_amount'} = '-\dollar '. $payment->{'amount'};
          push @total_fill, 
            map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
                @total_item;
        }
  
        $invoice_data{'total_item'} = '\textbf{'. $self->balance_due_msg. '}';
        $invoice_data{'total_amount'} =
          '\textbf{\dollar '. sprintf('%.2f', $self->owed + $pr_total ). '}';
        push @total_fill,
          map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
              @total_item;
  
        push @filled_in, @total_fill;
  
      } else {
        #$line =~ s/\$(\w+)/$invoice_data{$1}/eg;
        $line =~ s/\$(\w+)/exists($invoice_data{$1}) ? $invoice_data{$1} : nounder($1)/eg;
        push @filled_in, $line;
      }
  
    }

    sub nounder {
      my $var = $1;
      $var =~ s/_/\-/g;
      $var;
    }

  } elsif ( $format eq 'Text::Template' ) {

    my @detail_items = ();
    my @total_items = ();

    $invoice_data{'detail_items'} = \@detail_items;
    $invoice_data{'total_items'} = \@total_items;
  
    my %options = ( 'format' => 'latex', 'escape_function' => \&_latex_escape );
    foreach my $line_item ( ($conf->exists('disable_previous_balance') ? qw() : $self->_items_previous(%options)), $self->_items_pkg(%options) ) {
      my $detail = {
        ext_description => [],
      };
      $detail->{'ref'} = $line_item->{'pkgnum'};
      $detail->{'quantity'} = 1;
      $detail->{'description'} = _latex_escape($line_item->{'description'});
      if ( exists $line_item->{'ext_description'} ) {
        @{$detail->{'ext_description'}} = @{$line_item->{'ext_description'}};
      }
      $detail->{'amount'} = $line_item->{'amount'};
      $detail->{'unit_amount'} = $line_item->{'unit_amount'};
      $detail->{'product_code'} = $line_item->{'pkgpart'} || 'N/A';
  
      push @detail_items, $detail;
    }
  
  
    my $taxtotal = 0;
    foreach my $tax ( $self->_items_tax ) {
      my $total = {};
      $total->{'total_item'} = _latex_escape($tax->{'description'});
      $taxtotal += $tax->{'amount'};
      $total->{'total_amount'} = '\dollar '. $tax->{'amount'};
      push @total_items, $total;
    }
  
    if ( $taxtotal ) {
      $invoice_data{'taxtotal'} = sprintf('%.2f', $taxtotal);
      my $total = {};
      $total->{'total_item'} = 'Sub-total';
      $total->{'total_amount'} =
        '\dollar '. sprintf('%.2f', $self->charged - $taxtotal );
      unshift @total_items, $total;
    }else{
      $invoice_data{'taxtotal'} = '0.00';
    }
  
    {
      my $total = {};
      $total->{'total_item'} = '\textbf{Total}';
      $total->{'total_amount'} =
        '\textbf{\dollar '.
        sprintf( '%.2f',
                 $self->charged + ( $conf->exists('disable_previous_balance')
                                    ? 0
                                    : $pr_total
                                  )
               ).
      '}';
      push @total_items, $total;
    }
  
    unless ($conf->exists('disable_previous_balance')) {
      #foreach my $thing ( sort { $a->_date <=> $b->_date } $self->_items_credits, $self->_items_payments
  
      # credits
      my $credittotal = 0;
      foreach my $credit ( $self->_items_credits ) {
        my $total;
        $total->{'total_item'} = _latex_escape($credit->{'description'});
        $credittotal += $credit->{'amount'};
        $total->{'total_amount'} = '-\dollar '. $credit->{'amount'};
        push @total_items, $total;
      }
      $invoice_data{'credittotal'} = sprintf('%.2f', $credittotal);
  
      # payments
      my $paymenttotal = 0;
      foreach my $payment ( $self->_items_payments ) {
        my $total = {};
        $total->{'total_item'} = _latex_escape($payment->{'description'});
        $paymenttotal += $payment->{'amount'};
        $total->{'total_amount'} = '-\dollar '. $payment->{'amount'};
        push @total_items, $total;
      }
      $invoice_data{'paymenttotal'} = sprintf('%.2f', $paymenttotal);
  
      { 
        my $total;
        $total->{'total_item'} = '\textbf{'. $self->balance_due_msg. '}';
        $total->{'total_amount'} =
          '\textbf{\dollar '. sprintf('%.2f', $self->owed + $pr_total ). '}';
        push @total_items, $total;
      }
    }

  } else {
    die "guru meditation #54";
  }

  my $dir = $FS::UID::conf_dir. "cache.". $FS::UID::datasrc;
  my $fh = new File::Temp( TEMPLATE => 'invoice.'. $self->invnum. '.XXXXXXXX',
                           DIR      => $dir,
                           SUFFIX   => '.tex',
                           UNLINK   => 0,
                         ) or die "can't open temp file: $!\n";
  if ( $format eq 'old' ) {
    print $fh join('', @filled_in );
  } elsif ( $format eq 'Text::Template' ) {
    $text_template->fill_in(OUTPUT => $fh, HASH => \%invoice_data);
  } else {
    die "guru meditation #32";
  }
  close $fh;

  $fh->filename =~ /^(.*).tex$/ or die "unparsable filename: ". $fh->filename;
  return $1;

}

=item print_ps [ TIME [ , TEMPLATE ] ]

Returns an postscript invoice, as a scalar.

TIME an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=cut

sub print_ps {
  my $self = shift;

  my $file = $self->print_latex(@_);
  my $ps = generate_ps($file);
  
  $ps;
}

=item print_pdf [ TIME [ , TEMPLATE ] ]

Returns an PDF invoice, as a scalar.

TIME an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=cut

sub print_pdf {
  my $self = shift;

  my $file = $self->print_latex(@_);
  my $pdf = generate_pdf($file);
  
  $pdf;
}

=item print_html [ TIME [ , TEMPLATE [ , CID ] ] ]

Returns an HTML invoice, as a scalar.

TIME an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

CID is a MIME Content-ID used to create a "cid:" URL for the logo image, used
when emailing the invoice as part of a multipart/related MIME email.

=cut

#some falze laziness w/print_text and print_latex (and send_csv)
sub print_html {
  my( $self, $today, $template, $cid ) = @_;
  $today ||= time;

  my $cust_main = $self->cust_main;
  $cust_main->payname( $cust_main->first. ' '. $cust_main->getfield('last') )
    unless $cust_main->payname && $cust_main->payby !~ /^(CHEK|DCHK)$/;

  $template ||= $self->_agent_template;
  my $templatefile = 'invoice_html';
  my $suffix = length($template) ? "_$template" : '';
  $templatefile .= $suffix;
  my @html_template = map "$_\n", $conf->config($templatefile)
    or die "cannot load config file $templatefile";

  my $html_template = new Text::Template(
    TYPE   => 'ARRAY',
    SOURCE => \@html_template,
    DELIMITERS => [ '<%=', '%>' ],
  );

  $html_template->compile()
    or die 'While compiling ' . $templatefile . ': ' . $Text::Template::ERROR;

  my %invoice_data = (
    'custnum'      => $self->custnum,
    'invnum'       => $self->invnum,
    'date'         => time2str('%b&nbsp;%o,&nbsp;%Y', $self->_date),
    'today'        => time2str('%b %o, %Y', $today),
    'agent'        => encode_entities($cust_main->agent->agent),
    'agent_custid' => encode_entities($cust_main->agent_custid),
    'payname'      => encode_entities($cust_main->payname),
    'company'      => encode_entities($cust_main->company),
    'address1'     => encode_entities($cust_main->address1),
    'address2'     => encode_entities($cust_main->address2),
    'city'         => encode_entities($cust_main->city),
    'state'        => encode_entities($cust_main->state),
    'zip'          => encode_entities($cust_main->zip),
    'fax'          => encode_entities($cust_main->fax),
    'terms'        => $conf->config('invoice_default_terms')
                      || 'Payable upon receipt',
    'cid'          => $cid,
    'template'     => $template,
    'ship_enable'  => $conf->exists('invoice-ship_address'),
    'unitprices'   => $conf->exists('invoice-unitprice'),
#    'conf_dir'     => "$FS::UID::conf_dir/conf.$FS::UID::datasrc",
  );

  my $prefix = $cust_main->has_ship_address ? 'ship_' : '';
  foreach ( qw( contact company address1 address2 city state zip country fax) ){
    my $method = $prefix.$_;
    $invoice_data{"ship_$_"} = encode_entities($cust_main->$method);
  }

  if (
         defined( $conf->config_orbase('invoice_htmlreturnaddress', $template) )
      && length(  $conf->config_orbase('invoice_htmlreturnaddress', $template) )
  ) {
    $invoice_data{'returnaddress'} =
      join("\n", $conf->config_orbase('invoice_htmlreturnaddress', $template) );
  } else {
    $invoice_data{'returnaddress'} =
      join("\n", map { 
                       s/~/&nbsp;/g;
                       s/\\\\\*?\s*$/<BR>/;
                       s/\\hyphenation\{[\w\s\-]+\}//;
                       $_;
                     }
                     $conf->config_orbase( 'invoice_latexreturnaddress',
                                           $template
                                         )
          );
  }

  my $countrydefault = $conf->config('countrydefault') || 'US';
  if ( $cust_main->country eq $countrydefault ) {
    $invoice_data{'country'} = '';
  } else {
    $invoice_data{'country'} =
      encode_entities(code2country($cust_main->country));
  }

  if (
         defined( $conf->config_orbase('invoice_htmlnotes', $template) )
      && length(  $conf->config_orbase('invoice_htmlnotes', $template) )
  ) {
    $invoice_data{'notes'} =
      join("\n", $conf->config_orbase('invoice_htmlnotes', $template) );
  } else {
    $invoice_data{'notes'} = 
      join("\n", map { 
                       s/%%(.*)$/<!-- $1 -->/g;
                       s/\\section\*\{\\textsc\{(.)(.*)\}\}/<p><b><font size="+1">$1<\/font>\U$2<\/b>/g;
                       s/\\begin\{enumerate\}/<ol>/g;
                       s/\\item /  <li>/g;
                       s/\\end\{enumerate\}/<\/ol>/g;
                       s/\\textbf\{(.*)\}/<b>$1<\/b>/g;
                       s/\\\\\*/<br>/g;
                       s/\\dollar ?/\$/g;
                       s/\\#/#/g;
                       s/~/&nbsp;/g;
                       $_;
                     } 
                     $conf->config_orbase('invoice_latexnotes', $template)
          );
  }

#  #do variable substitutions in notes
#  $invoice_data{'notes'} =
#    join("\n",
#      map { my $b=$_; $b =~ s/\$(\w+)/$invoice_data{$1}/eg; $b }
#        $conf->config_orbase('invoice_latexnotes', $suffix)
#    );

  if (
         defined( $conf->config_orbase('invoice_htmlfooter', $template) )
      && length(  $conf->config_orbase('invoice_htmlfooter', $template) )
  ) {
   $invoice_data{'footer'} =
     join("\n", $conf->config_orbase('invoice_htmlfooter', $template) );
  } else {
   $invoice_data{'footer'} =
       join("\n", map { s/~/&nbsp;/g; s/\\\\\*?\s*$/<BR>/; $_; }
                      $conf->config_orbase('invoice_latexfooter', $template)
           );
  }

  $invoice_data{'po_line'} =
    (  $cust_main->payby eq 'BILL' && $cust_main->payinfo )
      ? encode_entities("Purchase Order #". $cust_main->payinfo)
      : '';

  my $money_char = $conf->config('money_char') || '$';

  my %options = ( 'format' => 'html', 'escape_function' => \&encode_entities );
  foreach my $line_item ( ($conf->exists('disable_previous_balance') ? qw() : $self->_items_previous(%options)), $self->_items_pkg(%options) ) {
    my $detail = {
      ext_description => [],
    };
    $detail->{'ref'} = $line_item->{'pkgnum'};
    $detail->{'description'} = encode_entities($line_item->{'description'});
    if ( exists $line_item->{'ext_description'} ) {
      @{$detail->{'ext_description'}} = @{$line_item->{'ext_description'}};
    }
    $detail->{'amount'} = $money_char. $line_item->{'amount'};
    $detail->{'product_code'} = $line_item->{'pkgpart'} || 'N/A';

    push @{$invoice_data{'detail_items'}}, $detail;
  }


  my $taxtotal = 0;
  foreach my $tax ( $self->_items_tax ) {
    my $total = {};
    $total->{'total_item'} = encode_entities($tax->{'description'});
    $taxtotal += $tax->{'amount'};
    $total->{'total_amount'} = $money_char. $tax->{'amount'};
    push @{$invoice_data{'total_items'}}, $total;
  }

  if ( $taxtotal ) {
    my $total = {};
    $total->{'total_item'} = 'Sub-total';
    $total->{'total_amount'} =
      $money_char. sprintf('%.2f', $self->charged - $taxtotal );
    unshift @{$invoice_data{'total_items'}}, $total;
  }

  my( $pr_total, @pr_cust_bill ) = $self->previous; #previous balance
  {
    my $total = {};
    $total->{'total_item'} = '<b>Total</b>';
    $total->{'total_amount'} =
      "<b>$money_char".
      sprintf( '%.2f',
               $self->charged + ( $conf->exists('disable_previous_balance')
                                  ? 0
                                  : $pr_total
                                )
             ).
      '</b>';
    push @{$invoice_data{'total_items'}}, $total;
  }

  unless ($conf->exists('disable_previous_balance')) {
    #foreach my $thing ( sort { $a->_date <=> $b->_date } $self->_items_credits, $self->_items_payments

    # credits
    foreach my $credit ( $self->_items_credits ) {
      my $total;
      $total->{'total_item'} = encode_entities($credit->{'description'});
      #$credittotal
      $total->{'total_amount'} = "-$money_char". $credit->{'amount'};
      push @{$invoice_data{'total_items'}}, $total;
    }

    # payments
    foreach my $payment ( $self->_items_payments ) {
      my $total = {};
      $total->{'total_item'} = encode_entities($payment->{'description'});
      #$paymenttotal
      $total->{'total_amount'} = "-$money_char". $payment->{'amount'};
      push @{$invoice_data{'total_items'}}, $total;
    }

    { 
      my $total;
      $total->{'total_item'} = '<b>'. $self->balance_due_msg. '</b>';
      $total->{'total_amount'} =
        "<b>$money_char".  sprintf('%.2f', $self->owed + $pr_total ). '</b>';
      push @{$invoice_data{'total_items'}}, $total;
    }
  }

  $html_template->fill_in( HASH => \%invoice_data);
}

# quick subroutine for print_latex
#
# There are ten characters that LaTeX treats as special characters, which
# means that they do not simply typeset themselves: 
#      # $ % & ~ _ ^ \ { }
#
# TeX ignores blanks following an escaped character; if you want a blank (as
# in "10% of ..."), you have to "escape" the blank as well ("10\%\ of ..."). 

sub _latex_escape {
  my $value = shift;
  $value =~ s/([#\$%&~_\^{}])( )?/"\\$1". ( ( defined($2) && length($2) ) ? "\\$2" : '' )/ge;
  $value =~ s/([<>])/\$$1\$/g;
  $value;
}

#utility methods for print_*

sub balance_due_msg {
  my $self = shift;
  my $msg = 'Balance Due';
  return $msg unless $conf->exists('invoice_default_terms');
  if ( $conf->config('invoice_default_terms') =~ /^\s*Net\s*(\d+)\s*$/ ) {
    $msg .= ' - Please pay by '. time2str("%x", $self->_date + ($1*86400) );
  } elsif ( $conf->config('invoice_default_terms') ) {
    $msg .= ' - '. $conf->config('invoice_default_terms');
  }
  $msg;
}

sub balance_due_date {
  my $self = shift;
  my $duedate = '';
  if (    $conf->exists('invoice_default_terms') 
       && $conf->config('invoice_default_terms')=~ /^\s*Net\s*(\d+)\s*$/ ) {
    $duedate = time2str("%m/%d/%Y", $self->_date + ($1*86400) );
  }
  $duedate;
}

=item invnum_date_pretty

Returns a string with the invoice number and date, for example:
"Invoice #54 (3/20/2008)"

=cut

sub invnum_date_pretty {
  my $self = shift;
  'Invoice #'. $self->invnum. ' ('. time2str('%x', $self->_date). ')';
}

sub _items {
  my $self = shift;

  #my @display = scalar(@_)
  #              ? @_
  #              : qw( _items_previous _items_pkg );
  #              #: qw( _items_pkg );
  #              #: qw( _items_previous _items_pkg _items_tax _items_credits _items_payments );
  my @display = qw( _items_previous _items_pkg );

  my @b = ();
  foreach my $display ( @display ) {
    push @b, $self->$display(@_);
  }
  @b;
}

sub _items_previous {
  my $self = shift;
  my $cust_main = $self->cust_main;
  my( $pr_total, @pr_cust_bill ) = $self->previous; #previous balance
  my @b = ();
  foreach ( @pr_cust_bill ) {
    push @b, {
      'description' => 'Previous Balance, Invoice #'. $_->invnum. 
                       ' ('. time2str('%x',$_->_date). ')',
      #'pkgpart'     => 'N/A',
      'pkgnum'      => 'N/A',
      'amount'      => sprintf("%.2f", $_->owed),
    };
  }
  @b;

  #{
  #    'description'     => 'Previous Balance',
  #    #'pkgpart'         => 'N/A',
  #    'pkgnum'          => 'N/A',
  #    'amount'          => sprintf("%10.2f", $pr_total ),
  #    'ext_description' => [ map {
  #                                 "Invoice ". $_->invnum.
  #                                 " (". time2str("%x",$_->_date). ") ".
  #                                 sprintf("%10.2f", $_->owed)
  #                         } @pr_cust_bill ],

  #};
}

sub _items_pkg {
  my $self = shift;
  my @cust_bill_pkg = grep { $_->pkgnum } $self->cust_bill_pkg;
  $self->_items_cust_bill_pkg(\@cust_bill_pkg, @_);
}

sub _items_tax {
  my $self = shift;
  my @cust_bill_pkg = grep { ! $_->pkgnum } $self->cust_bill_pkg;
  $self->_items_cust_bill_pkg(\@cust_bill_pkg, @_);
}

sub _items_cust_bill_pkg {
  my $self = shift;
  my $cust_bill_pkg = shift;
  my %opt = @_;

  my $format = $opt{format} || '';
  my $escape_function = $opt{escape_function} || sub { shift };

  my @b = ();
  foreach my $cust_bill_pkg ( @$cust_bill_pkg ) {

    my $cust_pkg = $cust_bill_pkg->cust_pkg;

    my $desc = $cust_bill_pkg->desc;

    my %details_opt = ( 'format'          => $format,
                        'escape_function' => $escape_function,
                      );

    if ( $cust_bill_pkg->pkgnum > 0 ) {

      if ( $cust_bill_pkg->setup != 0 ) {

        my $description = $desc;
        $description .= ' Setup' if $cust_bill_pkg->recur != 0;

        my @d = map &{$escape_function}($_),
                       $cust_pkg->h_labels_short($self->_date);
        push @d, $cust_bill_pkg->details(%details_opt)
          if $cust_bill_pkg->recur == 0;

        push @b, {
          description     => $description,
          #pkgpart         => $part_pkg->pkgpart,
          pkgnum          => $cust_bill_pkg->pkgnum,
          amount          => sprintf("%.2f", $cust_bill_pkg->setup),
          unit_amount     => sprintf("%.2f", $cust_bill_pkg->unitsetup),
          quantity        => $cust_bill_pkg->quantity,
          ext_description => \@d,
        };
      }

      if ( $cust_bill_pkg->recur != 0 ) {

        my $description = $desc;
        unless ( $conf->exists('disable_line_item_date_ranges') ) {
          $description .= " (" . time2str("%x", $cust_bill_pkg->sdate).
                          " - ". time2str("%x", $cust_bill_pkg->edate). ")";
        }

        #at least until cust_bill_pkg has "past" ranges in addition to
        #the "future" sdate/edate ones... see #3032
        my @d = map &{$escape_function}($_),
                    $cust_pkg->h_labels_short($self->_date);
                                              #$cust_bill_pkg->edate,
                                              #$cust_bill_pkg->sdate),
        push @d, $cust_bill_pkg->details(%details_opt);

        push @b, {
          description     => $description,
          #pkgpart         => $part_pkg->pkgpart,
          pkgnum          => $cust_bill_pkg->pkgnum,
          amount          => sprintf("%.2f", $cust_bill_pkg->recur),
          unit_amount     => sprintf("%.2f", $cust_bill_pkg->unitrecur),
          quantity        => $cust_bill_pkg->quantity,
          ext_description => \@d,
        };

      }

    } else { #pkgnum tax or one-shot line item (??)

      if ( $cust_bill_pkg->setup != 0 ) {
        push @b, {
          'description' => $desc,
          'amount'      => sprintf("%.2f", $cust_bill_pkg->setup),
        };
      }
      if ( $cust_bill_pkg->recur != 0 ) {
        push @b, {
          'description' => "$desc (".
                           time2str("%x", $cust_bill_pkg->sdate). ' - '.
                           time2str("%x", $cust_bill_pkg->edate). ')',
          'amount'      => sprintf("%.2f", $cust_bill_pkg->recur),
        };
      }

    }

  }

  @b;

}

sub _items_credits {
  my $self = shift;

  my @b;
  #credits
  foreach ( $self->cust_credited ) {

    #something more elaborate if $_->amount ne $_->cust_credit->credited ?

    my $reason = $_->cust_credit->reason;
    #my $reason = substr($_->cust_credit->reason,0,32);
    #$reason .= '...' if length($reason) < length($_->cust_credit->reason);
    $reason = " ($reason) " if $reason;
    push @b, {
      #'description' => 'Credit ref\#'. $_->crednum.
      #                 " (". time2str("%x",$_->cust_credit->_date) .")".
      #                 $reason,
      'description' => 'Credit applied '.
                       time2str("%x",$_->cust_credit->_date). $reason,
      'amount'      => sprintf("%.2f",$_->amount),
    };
  }
  #foreach ( @cr_cust_credit ) {
  #  push @buf,[
  #    "Credit #". $_->crednum. " (" . time2str("%x",$_->_date) .")",
  #    $money_char. sprintf("%10.2f",$_->credited)
  #  ];
  #}

  @b;

}

sub _items_payments {
  my $self = shift;

  my @b;
  #get & print payments
  foreach ( $self->cust_bill_pay ) {

    #something more elaborate if $_->amount ne ->cust_pay->paid ?

    push @b, {
      'description' => "Payment received ".
                       time2str("%x",$_->cust_pay->_date ),
      'amount'      => sprintf("%.2f", $_->amount )
    };
  }

  @b;

}


=back

=head1 SUBROUTINES

=over 4

=item process_reprint

=cut

sub process_reprint {
  process_re_X('print', @_);
}

=item process_reemail

=cut

sub process_reemail {
  process_re_X('email', @_);
}

=item process_refax

=cut

sub process_refax {
  process_re_X('fax', @_);
}

=item process_reftp

=cut

sub process_reftp {
  process_re_X('ftp', @_);
}

=item respool

=cut

sub process_respool {
  process_re_X('spool', @_);
}

use Storable qw(thaw);
use Data::Dumper;
use MIME::Base64;
sub process_re_X {
  my( $method, $job ) = ( shift, shift );
  warn "$me process_re_X $method for job $job\n" if $DEBUG;

  my $param = thaw(decode_base64(shift));
  warn Dumper($param) if $DEBUG;

  re_X(
    $method,
    $job,
    %$param,
  );

}

sub re_X {
  my($method, $job, %param ) = @_;
  if ( $DEBUG ) {
    warn "re_X $method for job $job with param:\n".
         join( '', map { "  $_ => ". $param{$_}. "\n" } keys %param );
  }

  #some false laziness w/search/cust_bill.html
  my $distinct = '';
  my $orderby = 'ORDER BY cust_bill._date';

  my $extra_sql = ' WHERE '. FS::cust_bill->search_sql(\%param);

  my $addl_from = 'LEFT JOIN cust_main USING ( custnum )';
     
  my @cust_bill = qsearch( {
    #'select'    => "cust_bill.*",
    'table'     => 'cust_bill',
    'addl_from' => $addl_from,
    'hashref'   => {},
    'extra_sql' => $extra_sql,
    'order_by'  => $orderby,
    'debug' => 1,
  } );

  $method .= '_invoice' unless $method eq 'email' || $method eq 'print';

  warn " $me re_X $method: ". scalar(@cust_bill). " invoices found\n"
    if $DEBUG;

  my( $num, $last, $min_sec ) = (0, time, 5); #progresbar foo
  foreach my $cust_bill ( @cust_bill ) {
    $cust_bill->$method();

    if ( $job ) { #progressbar foo
      $num++;
      if ( time - $min_sec > $last ) {
        my $error = $job->update_statustext(
          int( 100 * $num / scalar(@cust_bill) )
        );
        die $error if $error;
        $last = time;
      }
    }

  }

}

=back

=head1 CLASS METHODS

=over 4

=item owed_sql

Returns an SQL fragment to retreive the amount owed (charged minus credited and paid).

=cut

sub owed_sql {
  my $class = shift;
  'charged - '. $class->paid_sql. ' - '. $class->credited_sql;
}

=item net_sql

Returns an SQL fragment to retreive the net amount (charged minus credited).

=cut

sub net_sql {
  my $class = shift;
  'charged - '. $class->credited_sql;
}

=item paid_sql

Returns an SQL fragment to retreive the amount paid against this invoice.

=cut

sub paid_sql {
  #my $class = shift;
  "( SELECT COALESCE(SUM(amount),0) FROM cust_bill_pay
       WHERE cust_bill.invnum = cust_bill_pay.invnum   )";
}

=item credited_sql

Returns an SQL fragment to retreive the amount credited against this invoice.

=cut

sub credited_sql {
  #my $class = shift;
  "( SELECT COALESCE(SUM(amount),0) FROM cust_credit_bill
       WHERE cust_bill.invnum = cust_credit_bill.invnum   )";
}

=item search_sql HASHREF

Class method which returns an SQL WHERE fragment to search for parameters
specified in HASHREF.  Valid parameters are

=over 4

=item begin

Epoch date (UNIX timestamp) setting a lower bound for _date values

=item end

Epoch date (UNIX timestamp) setting an upper bound for _date values

=item invnum_min

=item invnum_max

=item agentnum

=item owed

=item net

=item days

=item newest_percust

=back

Note: validates all passed-in data; i.e. safe to use with unchecked CGI params.

=cut

sub search_sql {
  my($class, $param) = @_;
  if ( $DEBUG ) {
    warn "$me search_sql called with params: \n".
         join("\n", map { "  $_: ". $param->{$_} } keys %$param ). "\n";
  }

  my @search = ();

  if ( $param->{'begin'} =~ /^(\d+)$/ ) {
    push @search, "cust_bill._date >= $1";
  }
  if ( $param->{'end'} =~ /^(\d+)$/ ) {
    push @search, "cust_bill._date < $1";
  }
  if ( $param->{'invnum_min'} =~ /^(\d+)$/ ) {
    push @search, "cust_bill.invnum >= $1";
  }
  if ( $param->{'invnum_max'} =~ /^(\d+)$/ ) {
    push @search, "cust_bill.invnum <= $1";
  }
  if ( $param->{'agentnum'} =~ /^(\d+)$/ ) {
    push @search, "cust_main.agentnum = $1";
  }

  push @search, '0 != '. FS::cust_bill->owed_sql
    if $param->{'open'};

  push @search, '0 != '. FS::cust_bill->net_sql
    if $param->{'net'};

  push @search, "cust_bill._date < ". (time-86400*$param->{'days'})
    if $param->{'days'};

  if ( $param->{'newest_percust'} ) {

    #$distinct = 'DISTINCT ON ( cust_bill.custnum )';
    #$orderby = 'ORDER BY cust_bill.custnum ASC, cust_bill._date DESC';

    my @newest_where = map { my $x = $_;
                             $x =~ s/\bcust_bill\./newest_cust_bill./g;
                             $x;
                           }
                           grep ! /^cust_main./, @search;
    my $newest_where = scalar(@newest_where)
                         ? ' AND '. join(' AND ', @newest_where)
			 : '';


    push @search, "cust_bill._date = (
      SELECT(MAX(newest_cust_bill._date)) FROM cust_bill AS newest_cust_bill
        WHERE newest_cust_bill.custnum = cust_bill.custnum
          $newest_where
    )";

  }

  my $curuser = $FS::CurrentUser::CurrentUser;
  if ( $curuser->username eq 'fs_queue'
       && $param->{'CurrentUser'} =~ /^(\w+)$/ ) {
    my $username = $1;
    my $newuser = qsearchs('access_user', {
      'username' => $username,
      'disabled' => '',
    } );
    if ( $newuser ) {
      $curuser = $newuser;
    } else {
      warn "$me WARNING: (fs_queue) can't find CurrentUser $username\n";
    }
  }

  push @search, $curuser->agentnums_sql;

  join(' AND ', @search );

}

=back

=head1 BUGS

The delete method.

=head1 SEE ALSO

L<FS::Record>, L<FS::cust_main>, L<FS::cust_bill_pay>, L<FS::cust_pay>,
L<FS::cust_bill_pkg>, L<FS::cust_bill_credit>, schema.html from the base
documentation.

=cut

1;

