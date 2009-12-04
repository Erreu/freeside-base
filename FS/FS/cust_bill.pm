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
use Storable qw( freeze thaw );
use FS::UID qw( datasrc );
use FS::Misc qw( send_email send_fax generate_ps generate_pdf do_print );
use FS::Record qw( qsearch qsearchs dbh );
use FS::cust_main_Mixin;
use FS::cust_main;
use FS::cust_statement;
use FS::cust_bill_pkg;
use FS::cust_bill_pkg_display;
use FS::cust_bill_pkg_detail;
use FS::cust_credit;
use FS::cust_pay;
use FS::cust_pkg;
use FS::cust_credit_bill;
use FS::pay_batch;
use FS::cust_pay_batch;
use FS::cust_bill_event;
use FS::cust_event;
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

Regular fields

=over 4

=item invnum - primary key (assigned automatically for new invoices)

=item custnum - customer (see L<FS::cust_main>)

=item _date - specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=item charged - amount of this invoice

=item invoice_terms - optional terms override for this specific invoice

=back

Customer info at invoice generation time

=over 4

=item previous_balance

=item billing_balance

=back

Deprecated

=over 4

=item printed - deprecated

=back

Specific use cases

=over 4

=item closed - books closed flag, empty or `Y'

=item statementnum - invoice aggregation (see L<FS::cust_statement>)

=item agent_invid - legacy invoice number

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

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  foreach my $table (qw(
    cust_bill_event
    cust_event
    cust_credit_bill
    cust_bill_pay
    cust_bill_pay
    cust_credit_bill
    cust_pay_batch
    cust_bill_pay_batch
    cust_bill_pkg
  )) {

    foreach my $linked ( $self->$table() ) {
      my $error = $linked->delete;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return $error;
      }
    }

  }

  my $error = $self->SUPER::delete(@_);
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';

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
    || $self->ut_foreign_key('custnum', 'cust_main', 'custnum' )
    || $self->ut_numbern('_date')
    || $self->ut_money('charged')
    || $self->ut_numbern('printed')
    || $self->ut_enum('closed', [ '', 'Y' ])
    || $self->ut_foreign_keyn('statementnum', 'cust_statement', 'statementnum' )
    || $self->ut_numbern('agent_invid') #varchar?
  ;
  return $error if $error;

  $self->_date(time) unless $self->_date;

  $self->printed(0) if $self->printed eq '';

  $self->SUPER::check;
}

=item display_invnum

Returns the displayed invoice number for this invoice: agent_invid if
cust_bill-default_agent_invid is set and it has a value, invnum otherwise.

=cut

sub display_invnum {
  my $self = shift;
  if ( $conf->exists('cust_bill-default_agent_invid') && $self->agent_invid ){
    return $self->agent_invid;
  } else {
    return $self->invnum;
  }
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
  qsearch(
    { 'table'    => 'cust_bill_pkg',
      'hashref'  => { 'invnum' => $self->invnum },
      'order_by' => 'ORDER BY billpkgnum',
    }
  );
}

=item cust_bill_pkg_pkgnum PKGNUM

Returns the line items (see L<FS::cust_bill_pkg>) for this invoice and
specified pkgnum.

=cut

sub cust_bill_pkg_pkgnum {
  my( $self, $pkgnum ) = @_;
  qsearch(
    { 'table'    => 'cust_bill_pkg',
      'hashref'  => { 'invnum' => $self->invnum,
                      'pkgnum' => $pkgnum,
                    },
      'order_by' => 'ORDER BY billpkgnum',
    }
  );
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

Returns the completed invoice events (deprecated, old-style events - see L<FS::cust_bill_event>) for this invoice.

=cut

sub cust_bill_event {
  my $self = shift;
  qsearch( 'cust_bill_event', { 'invnum' => $self->invnum } );
}

=item num_cust_bill_event

Returns the number of completed invoice events (deprecated, old-style events - see L<FS::cust_bill_event>) for this invoice.

=cut

sub num_cust_bill_event {
  my $self = shift;
  my $sql =
    "SELECT COUNT(*) FROM cust_bill_event WHERE invnum = ?";
  my $sth = dbh->prepare($sql) or die  dbh->errstr. " preparing $sql"; 
  $sth->execute($self->invnum) or die $sth->errstr. " executing $sql";
  $sth->fetchrow_arrayref->[0];
}

=item cust_event

Returns the new-style customer billing events (see L<FS::cust_event>) for this invoice.

=cut

#false laziness w/cust_pkg.pm
sub cust_event {
  my $self = shift;
  qsearch({
    'table'     => 'cust_event',
    'addl_from' => 'JOIN part_event USING ( eventpart )',
    'hashref'   => { 'tablenum' => $self->invnum },
    'extra_sql' => " AND eventtable = 'cust_bill' ",
  });
}

=item num_cust_event

Returns the number of new-style customer billing events (see L<FS::cust_event>) for this invoice.

=cut

#false laziness w/cust_pkg.pm
sub num_cust_event {
  my $self = shift;
  my $sql =
    "SELECT COUNT(*) FROM cust_event JOIN part_event USING ( eventpart ) ".
    "  WHERE tablenum = ? AND eventtable = 'cust_bill'";
  my $sth = dbh->prepare($sql) or die  dbh->errstr. " preparing $sql"; 
  $sth->execute($self->invnum) or die $sth->errstr. " executing $sql";
  $sth->fetchrow_arrayref->[0];
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

sub cust_pay_batch {
  my $self = shift;
  qsearch('cust_pay_batch', { 'invnum' => $self->invnum } );
}

sub cust_bill_pay_batch {
  my $self = shift;
  qsearch('cust_bill_pay_batch', { 'invnum' => $self->invnum } );
}

=item cust_bill_pay

Returns all payment applications (see L<FS::cust_bill_pay>) for this invoice.

=cut

sub cust_bill_pay {
  my $self = shift;
  map { $_ } #return $self->num_cust_bill_pay unless wantarray;
  sort { $a->_date <=> $b->_date }
    qsearch( 'cust_bill_pay', { 'invnum' => $self->invnum } );
}

=item cust_credited

=item cust_credit_bill

Returns all applied credits (see L<FS::cust_credit_bill>) for this invoice.

=cut

sub cust_credited {
  my $self = shift;
  map { $_ } #return $self->num_cust_credit_bill unless wantarray;
  sort { $a->_date <=> $b->_date }
    qsearch( 'cust_credit_bill', { 'invnum' => $self->invnum } )
  ;
}

sub cust_credit_bill {
  shift->cust_credited(@_);
}

=item cust_bill_pay_pkgnum PKGNUM

Returns all payment applications (see L<FS::cust_bill_pay>) for this invoice
with matching pkgnum.

=cut

sub cust_bill_pay_pkgnum {
  my( $self, $pkgnum ) = @_;
  map { $_ } #return $self->num_cust_bill_pay_pkgnum($pkgnum) unless wantarray;
  sort { $a->_date <=> $b->_date }
    qsearch( 'cust_bill_pay', { 'invnum' => $self->invnum,
                                'pkgnum' => $pkgnum,
                              }
           );
}

=item cust_credited_pkgnum PKGNUM

=item cust_credit_bill_pkgnum PKGNUM

Returns all applied credits (see L<FS::cust_credit_bill>) for this invoice
with matching pkgnum.

=cut

sub cust_credited_pkgnum {
  my( $self, $pkgnum ) = @_;
  map { $_ } #return $self->num_cust_credit_bill_pkgnum($pkgnum) unless wantarray;
  sort { $a->_date <=> $b->_date }
    qsearch( 'cust_credit_bill', { 'invnum' => $self->invnum,
                                   'pkgnum' => $pkgnum,
                                 }
           );
}

sub cust_credit_bill_pkgnum {
  shift->cust_credited_pkgnum(@_);
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

sub owed_pkgnum {
  my( $self, $pkgnum ) = @_;

  #my $balance = $self->charged;
  my $balance = 0;
  $balance += $_->setup + $_->recur for $self->cust_bill_pkg_pkgnum($pkgnum);

  $balance -= $_->amount            for $self->cust_bill_pay_pkgnum($pkgnum);
  $balance -= $_->amount            for $self->cust_credited_pkgnum($pkgnum);

  $balance = sprintf( "%.2f", $balance);
  $balance =~ s/^\-0\.00$/0.00/; #yay ieee fp
  $balance;
}

=item apply_payments_and_credits [ OPTION => VALUE ... ]

Applies unapplied payments and credits to this invoice.

A hash of optional arguments may be passed.  Currently "manual" is supported.
If true, a payment receipt is sent instead of a statement when
'payment_receipt_email' configuration option is set.

If there is an error, returns the error, otherwise returns false.

=cut

sub apply_payments_and_credits {
  my( $self, %options ) = @_;

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

  if ( $conf->exists('pkg-balances') ) {
    # limit @payments & @credits to those w/ a pkgnum grepped from $self
    my %pkgnums = map { $_ => 1 } map $_->pkgnum, $self->cust_bill_pkg;
    @payments = grep { ! $_->pkgnum || $pkgnums{$_->pkgnum} } @payments;
    @credits  = grep { ! $_->pkgnum || $pkgnums{$_->pkgnum} } @credits;
  }

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

    my $unapp_amount;
    if ( $app eq 'pay' ) {

      my $payment = shift @payments;
      $unapp_amount = $payment->unapplied;
      $app = new FS::cust_bill_pay { 'paynum'  => $payment->paynum };
      $app->pkgnum( $payment->pkgnum )
        if $conf->exists('pkg-balances') && $payment->pkgnum;

    } elsif ( $app eq 'credit' ) {

      my $credit = shift @credits;
      $unapp_amount = $credit->credited;
      $app = new FS::cust_credit_bill { 'crednum' => $credit->crednum };
      $app->pkgnum( $credit->pkgnum )
        if $conf->exists('pkg-balances') && $credit->pkgnum;

    } else {
      die "guru meditation #12 and 35";
    }

    my $owed;
    if ( $conf->exists('pkg-balances') && $app->pkgnum ) {
      warn "owed_pkgnum ". $app->pkgnum;
      $owed = $self->owed_pkgnum($app->pkgnum);
    } else {
      $owed = $self->owed;
    }
    next unless $owed > 0;

    warn "min ( $unapp_amount, $owed )\n" if $DEBUG;
    $app->amount( sprintf('%.2f', min( $unapp_amount, $owed ) ) );

    $app->invnum( $self->invnum );

    my $error = $app->insert(%options);
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "Error inserting ". $app->table. " record: $error";
    }
    die $error if $error;

  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  ''; #no error

}

=item generate_email OPTION => VALUE ...

Options:

=over 4

=item from

sender address, required

=item tempate

alternate template name, optional

=item print_text

text attachment arrayref, optional

=item subject

email subject, optional

=item notice_name

notice name instead of "Invoice", optional

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

  my %opt = (
    'unsquelch_cdr' => $conf->exists('voip-cdr_email'),
    'template'      => $args{'template'},
    'notice_name'   => ( $args{'notice_name'} || 'Invoice' ),
  );

  my $cust_main = $self->cust_main;

  if (ref($args{'to'}) eq 'ARRAY') {
    $return{'to'} = $args{'to'};
  } else {
    $return{'to'} = [ grep { $_ !~ /^(POST|FAX)$/ }
                           $cust_main->invoicing_list
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
        $data = [ $self->print_text(\%opt) ];
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

    my $logo;
    my $agentnum = $cust_main->agentnum;
    if ( defined($args{'template'}) && length($args{'template'})
         && $conf->exists( 'logo_'. $args{'template'}. '.png', $agentnum )
       )
    {
      $logo = 'logo_'. $args{'template'}. '.png';
    } else {
      $logo = "logo.png";
    }
    my $image_data = $conf->config_binary( $logo, $agentnum);

    my $image = build MIME::Entity
      'Type'       => 'image/png',
      'Encoding'   => 'base64',
      'Data'       => $image_data,
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
                         $self->print_html({ 'cid'=>$content_id, %opt }),
                         '  </body>',
                         '</html>',
                       ],
      'Disposition' => 'inline',
      #'Filename'    => 'invoice.pdf',
    );

    my @otherparts = ();
    if ( $cust_main->email_csv_cdr ) {

      push @otherparts, build MIME::Entity
        'Type'        => 'text/csv',
        'Encoding'    => '7bit',
        'Data'        => [ map { "$_\n" }
                             $self->call_details('prepend_billed_number' => 1)
                         ],
        'Disposition' => 'attachment',
        'Filename'    => 'usage-'. $self->invnum. '.csv',
      ;

    }

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

      my $pdf = build MIME::Entity $self->mimebuild_pdf(\%opt);

      $return{'mimeparts'} = [ $related, $pdf, @otherparts ];

    } else {

      #no other attachment:
      # multipart/related
      #   multipart/alternative
      #     text/plain
      #     text/html
      #   image/png

      $return{'content-type'} = 'multipart/related';
      $return{'mimeparts'} = [ $alternative, $image, @otherparts ];
      $return{'type'} = 'multipart/alternative'; #Content-Type of first part...
      #$return{'disposition'} = 'inline';

    }
  
  } else {

    if ( $conf->exists('invoice_email_pdf') ) {
      warn "$me creating PDF attachment"
        if $DEBUG;

      #mime parts arguments a la MIME::Entity->build().
      $return{'mimeparts'} = [
        { $self->mimebuild_pdf(\%opt) }
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
        $return{'body'} = [ $self->print_text(\%opt) ];
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
    'Filename'    => 'invoice-'. $self->invnum. '.pdf',
  );
}

=item send HASHREF | [ TEMPLATE [ , AGENTNUM [ , INVOICE_FROM [ , AMOUNT ] ] ] ]

Sends this invoice to the destinations configured for this customer: sends
email, prints and/or faxes.  See L<FS::cust_main_invoice>.

Options can be passed as a hashref (recommended) or as a list of up to 
four values for templatename, agentnum, invoice_from and amount.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<agentnum>, if specified, means that this invoice will only be sent for customers
of the specified agent or agent(s).  AGENTNUM can be a scalar agentnum (for a
single agent) or an arrayref of agentnums.

I<invoice_from>, if specified, overrides the default email invoice From: address.

I<amount>, if specified, only sends the invoice if the total amount owed on this
invoice and all older invoices is greater than the specified amount.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

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

  my( $template, $invoice_from, $notice_name );
  my $agentnums = '';
  my $balance_over = 0;

  if ( ref($_[0]) ) {
    my $opt = shift;
    $template = $opt->{'template'} || '';
    if ( $agentnums = $opt->{'agentnum'} ) {
      $agentnums = [ $agentnums ] unless ref($agentnums);
    }
    $invoice_from = $opt->{'invoice_from'};
    $balance_over = $opt->{'balance_over'} if $opt->{'balance_over'};
    $notice_name = $opt->{'notice_name'};
  } else {
    $template = scalar(@_) ? shift : '';
    if ( scalar(@_) && $_[0]  ) {
      $agentnums = ref($_[0]) ? shift : [ shift ];
    }
    $invoice_from = shift if scalar(@_);
    $balance_over = shift if scalar(@_) && $_[0] !~ /^\s*$/;
  }

  return 'N/A' unless ! $agentnums
                   or grep { $_ == $self->cust_main->agentnum } @$agentnums;

  return ''
    unless $self->cust_main->total_owed_date($self->_date) > $balance_over;

  $invoice_from ||= $self->_agent_invoice_from ||    #XXX should go away
                    $conf->config('invoice_from', $self->cust_main->agentnum );

  my %opt = (
    'template'     => $template,
    'invoice_from' => $invoice_from,
    'notice_name'  => ( $notice_name || 'Invoice' ),
  );

  my @invoicing_list = $self->cust_main->invoicing_list;

  #$self->email_invoice(\%opt)
  $self->email(\%opt)
    if grep { $_ !~ /^(POST|FAX)$/ } @invoicing_list or !@invoicing_list;

  #$self->print_invoice(\%opt)
  $self->print(\%opt)
    if grep { $_ eq 'POST' } @invoicing_list; #postal

  $self->fax_invoice(\%opt)
    if grep { $_ eq 'FAX' } @invoicing_list; #fax

  '';

}

=item email HASHREF | [ TEMPLATE [ , INVOICE_FROM ] ] 

Emails this invoice.

Options can be passed as a hashref (recommended) or as a list of up to 
two values for templatename and invoice_from.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<invoice_from>, if specified, overrides the default email invoice From: address.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

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

  my( $template, $invoice_from, $notice_name );
  if ( ref($_[0]) ) {
    my $opt = shift;
    $template = $opt->{'template'} || '';
    $invoice_from = $opt->{'invoice_from'};
    $notice_name = $opt->{'notice_name'} || 'Invoice';
  } else {
    $template = scalar(@_) ? shift : '';
    $invoice_from = shift if scalar(@_);
    $notice_name = 'Invoice';
  }

  $invoice_from ||= $self->_agent_invoice_from ||    #XXX should go away
                    $conf->config('invoice_from', $self->cust_main->agentnum );

  my @invoicing_list = grep { $_ !~ /^(POST|FAX)$/ } 
                            $self->cust_main->invoicing_list;

  #better to notify this person than silence
  @invoicing_list = ($invoice_from) unless @invoicing_list;

  my $subject = $self->email_subject($template);

  my $error = send_email(
    $self->generate_email(
      'from'        => $invoice_from,
      'to'          => [ grep { $_ !~ /^(POST|FAX)$/ } @invoicing_list ],
      'subject'     => $subject,
      'template'    => $template,
      'notice_name' => $notice_name,
    )
  );
  die "can't email invoice: $error\n" if $error;
  #die "$error\n" if $error;

}

sub email_subject {
  my $self = shift;

  #my $template = scalar(@_) ? shift : '';
  #per-template?

  my $subject = $conf->config('invoice_subject', $self->cust_main->agentnum)
                || 'Invoice';

  my $cust_main = $self->cust_main;
  my $name = $cust_main->name;
  my $name_short = $cust_main->name_short;
  my $invoice_number = $self->invnum;
  my $invoice_date = $self->_date_pretty;

  eval qq("$subject");
}

=item lpr_data HASHREF | [ TEMPLATE ]

Returns the postscript or plaintext for this invoice as an arrayref.

Options can be passed as a hashref (recommended) or as a single optional value
for template.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

sub lpr_data {
  my $self = shift;
  my( $template, $notice_name );
  if ( ref($_[0]) ) {
    my $opt = shift;
    $template = $opt->{'template'} || '';
    $notice_name = $opt->{'notice_name'} || 'Invoice';
  } else {
    $template = scalar(@_) ? shift : '';
    $notice_name = 'Invoice';
  }

  my %opt = (
    'template'    => $template,
    'notice_name' => $notice_name,
  );

  my $method = $conf->exists('invoice_latex') ? 'print_ps' : 'print_text';
  [ $self->$method( \%opt ) ];
}

=item print HASHREF | [ TEMPLATE ]

Prints this invoice.

Options can be passed as a hashref (recommended) or as a single optional
value for template.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

#sub print_invoice {
sub print {
  my $self = shift;
  my( $template, $notice_name );
  if ( ref($_[0]) ) {
    my $opt = shift;
    $template = $opt->{'template'} || '';
    $notice_name = $opt->{'notice_name'} || 'Invoice';
  } else {
    $template = scalar(@_) ? shift : '';
    $notice_name = 'Invoice';
  }

  my %opt = (
    'template'    => $template,
    'notice_name' => $notice_name,
  );

  do_print $self->lpr_data(\%opt);
}

=item fax_invoice HASHREF | [ TEMPLATE ] 

Faxes this invoice.

Options can be passed as a hashref (recommended) or as a single optional
value for template.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

sub fax_invoice {
  my $self = shift;
  my( $template, $notice_name );
  if ( ref($_[0]) ) {
    my $opt = shift;
    $template = $opt->{'template'} || '';
    $notice_name = $opt->{'notice_name'} || 'Invoice';
  } else {
    $template = scalar(@_) ? shift : '';
    $notice_name = 'Invoice';
  }

  die 'FAX invoice destination not (yet?) supported with plain text invoices.'
    unless $conf->exists('invoice_latex');

  my $dialstring = $self->cust_main->getfield('fax');
  #Check $dialstring?

  my %opt = (
    'template'    => $template,
    'notice_name' => $notice_name,
  );

  my $error = send_fax( 'docdata'    => $self->lpr_data(\%opt),
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

    my $duedate = $self->due_date2str('%m/%d/%Y'); #date_format?

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
          $cust_bill_pkg->part_pkg->pkg,
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
        $pkg = $cust_bill_pkg->desc;
        $setup = sprintf('%10.2f', $cust_bill_pkg->setup );
        ( $sdate, $edate ) = ( '', '' );
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
      map { $_->part_pkg->pkg }
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

=item print_text HASHREF | [ TIME [ , TEMPLATE [ , OPTION => VALUE ... ] ] ]

Returns an text invoice, as a list of lines.

Options can be passed as a hashref (recommended) or as a list of time, template
and then any key/value pairs for any other options.

I<time>, if specified, is used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

sub print_text {
  my $self = shift;
  my( $today, $template, %opt );
  if ( ref($_[0]) ) {
    %opt = %{ shift() };
    $today = delete($opt{'time'}) || '';
    $template = delete($opt{template}) || '';
  } else {
    ( $today, $template, %opt ) = @_;
  }

  my %params = ( 'format' => 'template' );
  $params{'time'} = $today if $today;
  $params{'template'} = $template if $template;
  $params{$_} = $opt{$_} 
    foreach grep $opt{$_}, qw( unsquealch_cdr notice_name );

  $self->print_generic( %params );
}

=item print_latex HASHREF | [ TIME [ , TEMPLATE [ , OPTION => VALUE ... ] ] ]

Internal method - returns a filename of a filled-in LaTeX template for this
invoice (Note: add ".tex" to get the actual filename), and a filename of
an associated logo (with the .eps extension included).

See print_ps and print_pdf for methods that return PostScript and PDF output.

Options can be passed as a hashref (recommended) or as a list of time, template
and then any key/value pairs for any other options.

I<time>, if specified, is used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

sub print_latex {
  my $self = shift;
  my( $today, $template, %opt );
  if ( ref($_[0]) ) {
    %opt = %{ shift() };
    $today = delete($opt{'time'}) || '';
    $template = delete($opt{template}) || '';
  } else {
    ( $today, $template, %opt ) = @_;
  }

  my %params = ( 'format' => 'latex' );
  $params{'time'} = $today if $today;
  $params{'template'} = $template if $template;
  $params{$_} = $opt{$_} 
    foreach grep $opt{$_}, qw( unsquealch_cdr notice_name );

  $template ||= $self->_agent_template;

  my $dir = $FS::UID::conf_dir. "/cache.". $FS::UID::datasrc;
  my $lh = new File::Temp( TEMPLATE => 'invoice.'. $self->invnum. '.XXXXXXXX',
                           DIR      => $dir,
                           SUFFIX   => '.eps',
                           UNLINK   => 0,
                         ) or die "can't open temp file: $!\n";

  my $agentnum = $self->cust_main->agentnum;

  if ( $template && $conf->exists("logo_${template}.eps", $agentnum) ) {
    print $lh $conf->config_binary("logo_${template}.eps", $agentnum)
      or die "can't write temp file: $!\n";
  } else {
    print $lh $conf->config_binary('logo.eps', $agentnum)
      or die "can't write temp file: $!\n";
  }
  close $lh;
  $params{'logo_file'} = $lh->filename;

  my @filled_in = $self->print_generic( %params );
  
  my $fh = new File::Temp( TEMPLATE => 'invoice.'. $self->invnum. '.XXXXXXXX',
                           DIR      => $dir,
                           SUFFIX   => '.tex',
                           UNLINK   => 0,
                         ) or die "can't open temp file: $!\n";
  print $fh join('', @filled_in );
  close $fh;

  $fh->filename =~ /^(.*).tex$/ or die "unparsable filename: ". $fh->filename;
  return ($1, $params{'logo_file'});

}

=item print_generic OPTION => VALUE ...

Internal method - returns a filled-in template for this invoice as a scalar.

See print_ps and print_pdf for methods that return PostScript and PDF output.

Non optional options include 
  format - latex, html, template

Optional options include

template - a value used as a suffix for a configuration template

time - a value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

cid - 

unsquelch_cdr - overrides any per customer cdr squelching when true

notice_name - overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

#what's with all the sprintf('%10.2f')'s in here?  will it cause any
# (alignment in text invoice?) problems to change them all to '%.2f' ?
# yes: fixed width (dot matrix) text printing will be borked
sub print_generic {

  my( $self, %params ) = @_;
  my $today = $params{today} ? $params{today} : time;
  warn "$me print_generic called on $self with suffix $params{template}\n"
    if $DEBUG;

  my $format = $params{format};
  die "Unknown format: $format"
    unless $format =~ /^(latex|html|template)$/;

  my $cust_main = $self->cust_main;
  $cust_main->payname( $cust_main->first. ' '. $cust_main->getfield('last') )
    unless $cust_main->payname
        && $cust_main->payby !~ /^(CARD|DCRD|CHEK|DCHK)$/;

  my %delimiters = ( 'latex'    => [ '[@--', '--@]' ],
                     'html'     => [ '<%=', '%>' ],
                     'template' => [ '{', '}' ],
                   );

  #create the template
  my $template = $params{template} ? $params{template} : $self->_agent_template;
  my $templatefile = "invoice_$format";
  $templatefile .= "_$template"
    if length($template);
  my @invoice_template = map "$_\n", $conf->config($templatefile)
    or die "cannot load config data $templatefile";

  my $old_latex = '';
  if ( $format eq 'latex' && grep { /^%%Detail/ } @invoice_template ) {
    #change this to a die when the old code is removed
    warn "old-style invoice template $templatefile; ".
         "patch with conf/invoice_latex.diff or use new conf/invoice_latex*\n";
    $old_latex = 'true';
    @invoice_template = _translate_old_latex_format(@invoice_template);
  } 

  my $text_template = new Text::Template(
    TYPE => 'ARRAY',
    SOURCE => \@invoice_template,
    DELIMITERS => $delimiters{$format},
  );

  $text_template->compile()
    or die "Can't compile $templatefile: $Text::Template::ERROR\n";


  # additional substitution could possibly cause breakage in existing templates
  my %convert_maps = ( 
    'latex' => {
                 'notes'         => sub { map "$_", @_ },
                 'footer'        => sub { map "$_", @_ },
                 'smallfooter'   => sub { map "$_", @_ },
                 'returnaddress' => sub { map "$_", @_ },
                 'coupon'        => sub { map "$_", @_ },
                 'summary'       => sub { map "$_", @_ },
               },
    'html'  => {
                 'notes' =>
                   sub {
                     map { 
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
                     }  @_
                   },
                 'footer' =>
                   sub { map { s/~/&nbsp;/g; s/\\\\\*?\s*$/<BR>/; $_; } @_ },
                 'smallfooter' =>
                   sub { map { s/~/&nbsp;/g; s/\\\\\*?\s*$/<BR>/; $_; } @_ },
                 'returnaddress' =>
                   sub {
                     map { 
                       s/~/&nbsp;/g;
                       s/\\\\\*?\s*$/<BR>/;
                       s/\\hyphenation\{[\w\s\-]+}//;
                       s/\\([&])/$1/g;
                       $_;
                     }  @_
                   },
                 'coupon'        => sub { "" },
                 'summary'       => sub { "" },
               },
    'template' => {
                 'notes' =>
                   sub {
                     map { 
                       s/%%.*$//g;
                       s/\\section\*\{\\textsc\{(.*)\}\}/\U$1/g;
                       s/\\begin\{enumerate\}//g;
                       s/\\item /  * /g;
                       s/\\end\{enumerate\}//g;
                       s/\\textbf\{(.*)\}/$1/g;
                       s/\\\\\*/ /;
                       s/\\dollar ?/\$/g;
                       $_;
                     }  @_
                   },
                 'footer' =>
                   sub { map { s/~/ /g; s/\\\\\*?\s*$/\n/; $_; } @_ },
                 'smallfooter' =>
                   sub { map { s/~/ /g; s/\\\\\*?\s*$/\n/; $_; } @_ },
                 'returnaddress' =>
                   sub {
                     map { 
                       s/~/ /g;
                       s/\\\\\*?\s*$/\n/;             # dubious
                       s/\\hyphenation\{[\w\s\-]+}//;
                       $_;
                     }  @_
                   },
                 'coupon'        => sub { "" },
                 'summary'       => sub { "" },
               },
  );


  # hashes for differing output formats
  my %nbsps = ( 'latex'    => '~',
                'html'     => '',    # '&nbps;' would be nice
                'template' => '',    # not used
              );
  my $nbsp = $nbsps{$format};

  my %escape_functions = ( 'latex'    => \&_latex_escape,
                           'html'     => \&encode_entities,
                           'template' => sub { shift },
                         );
  my $escape_function = $escape_functions{$format};

  my %date_formats = ( 'latex'    => '%b %o, %Y',
                       'html'     => '%b&nbsp;%o,&nbsp;%Y',
                       'template' => '%s',
                     );
  my $date_format = $date_formats{$format};

  my %embolden_functions = ( 'latex'    => sub { return '\textbf{'. shift(). '}'
                                               },
                             'html'     => sub { return '<b>'. shift(). '</b>'
                                               },
                             'template' => sub { shift },
                           );
  my $embolden_function = $embolden_functions{$format};


  # generate template variables
  my $returnaddress;
  if (
         defined( $conf->config_orbase( "invoice_${format}returnaddress",
                                        $template
                                      )
                )
       && length( $conf->config_orbase( "invoice_${format}returnaddress",
                                        $template
                                      )
                )
  ) {

    $returnaddress = join("\n",
      $conf->config_orbase("invoice_${format}returnaddress", $template)
    );

  } elsif ( grep /\S/,
            $conf->config_orbase('invoice_latexreturnaddress', $template) ) {

    my $convert_map = $convert_maps{$format}{'returnaddress'};
    $returnaddress =
      join( "\n",
            &$convert_map( $conf->config_orbase( "invoice_latexreturnaddress",
                                                 $template
                                               )
                         )
          );
  } elsif ( grep /\S/, $conf->config('company_address', $self->cust_main->agentnum) ) {

    my $convert_map = $convert_maps{$format}{'returnaddress'};
    $returnaddress = join( "\n", &$convert_map(
                                   map { s/( {2,})/'~' x length($1)/eg;
                                         s/$/\\\\\*/;
                                         $_
                                       }
                                     ( $conf->config('company_name', $self->cust_main->agentnum),
                                       $conf->config('company_address', $self->cust_main->agentnum),
                                     )
                                 )
                     );

  } else {

    my $warning = "Couldn't find a return address; ".
                  "do you need to set the company_address configuration value?";
    warn "$warning\n";
    $returnaddress = $nbsp;
    #$returnaddress = $warning;

  }

  my %invoice_data = (

    #invoice from info
    'company_name'    => scalar( $conf->config('company_name', $self->cust_main->agentnum) ),
    'company_address' => join("\n", $conf->config('company_address', $self->cust_main->agentnum) ). "\n",
    'returnaddress'   => $returnaddress,
    'agent'           => &$escape_function($cust_main->agent->agent),

    #invoice info
    'invnum'          => $self->invnum,
    'date'            => time2str($date_format, $self->_date),
    'today'           => time2str('%b %o, %Y', $today),
    'terms'           => $self->terms,
    'template'        => $template, #params{'template'},
    'notice_name'     => ($params{'notice_name'} || 'Invoice'),#escape_function?
    'current_charges' => sprintf("%.2f", $self->charged),
    'duedate'         => $self->due_date2str('%m/%d/%Y'), #date_format?

    #customer info
    'custnum'         => $cust_main->display_custnum,
    'agent_custid'    => &$escape_function($cust_main->agent_custid),
    ( map { $_ => &$escape_function($cust_main->$_()) } qw(
      payname company address1 address2 city state zip fax
    )),

    #global config
    'ship_enable'     => $conf->exists('invoice-ship_address'),
    'unitprices'      => $conf->exists('invoice-unitprice'),
    'smallernotes'    => $conf->exists('invoice-smallernotes'),
    'smallerfooter'   => $conf->exists('invoice-smallerfooter'),
   
    # better hang on to conf_dir for a while (for old templates)
    'conf_dir'        => "$FS::UID::conf_dir/conf.$FS::UID::datasrc",

    #these are only used when doing paged plaintext
    'page'            => 1,
    'total_pages'     => 1,

  );

  $invoice_data{finance_section} = '';
  if ( $conf->config('finance_pkgclass') ) {
    my $pkg_class =
      qsearchs('pkg_class', { classnum => $conf->config('finance_pkgclass') });
    $invoice_data{finance_section} = $pkg_class->categoryname;
  } 
 $invoice_data{finance_amount} = '0.00';

  my $countrydefault = $conf->config('countrydefault') || 'US';
  my $prefix = $cust_main->has_ship_address ? 'ship_' : '';
  foreach ( qw( contact company address1 address2 city state zip country fax) ){
    my $method = $prefix.$_;
    $invoice_data{"ship_$_"} = _latex_escape($cust_main->$method);
  }
  $invoice_data{'ship_country'} = ''
    if ( $invoice_data{'ship_country'} eq $countrydefault );
  
  $invoice_data{'cid'} = $params{'cid'}
    if $params{'cid'};

  if ( $cust_main->country eq $countrydefault ) {
    $invoice_data{'country'} = '';
  } else {
    $invoice_data{'country'} = &$escape_function(code2country($cust_main->country));
  }

  my @address = ();
  $invoice_data{'address'} = \@address;
  push @address,
    $cust_main->payname.
      ( ( $cust_main->payby eq 'BILL' ) && $cust_main->payinfo
        ? " (P.O. #". $cust_main->payinfo. ")"
        : ''
      )
  ;
  push @address, $cust_main->company
    if $cust_main->company;
  push @address, $cust_main->address1;
  push @address, $cust_main->address2
    if $cust_main->address2;
  push @address,
    $cust_main->city. ", ". $cust_main->state. "  ".  $cust_main->zip;
  push @address, $invoice_data{'country'}
    if $invoice_data{'country'};
  push @address, ''
    while (scalar(@address) < 5);

  $invoice_data{'logo_file'} = $params{'logo_file'}
    if $params{'logo_file'};

  my( $pr_total, @pr_cust_bill ) = $self->previous; #previous balance
#  my( $cr_total, @cr_cust_credit ) = $self->cust_credit; #credits
  #my $balance_due = $self->owed + $pr_total - $cr_total;
  my $balance_due = $self->owed + $pr_total;
  $invoice_data{'true_previous_balance'} = sprintf("%.2f", ($self->previous_balance || 0) );
  $invoice_data{'balance_adjustments'} = sprintf("%.2f", ($self->previous_balance || 0) - ($self->billing_balance || 0) );
  $invoice_data{'previous_balance'} = sprintf("%.2f", $pr_total);
  $invoice_data{'balance'} = sprintf("%.2f", $balance_due);

  my $agentnum = $self->cust_main->agentnum;

  my $summarypage = '';
  if ( $conf->exists('invoice_usesummary', $agentnum) ) {
    $summarypage = 1;
  }
  $invoice_data{'summarypage'} = $summarypage;

  #do variable substitution in notes, footer, smallfooter
  foreach my $include (qw( notes footer smallfooter coupon )) {

    my $inc_file = $conf->key_orbase("invoice_${format}$include", $template);
    my @inc_src;

    if ( $conf->exists($inc_file, $agentnum)
         && length( $conf->config($inc_file, $agentnum) ) ) {

      @inc_src = $conf->config($inc_file, $agentnum);

    } else {

      $inc_file = $conf->key_orbase("invoice_latex$include", $template);

      my $convert_map = $convert_maps{$format}{$include};

      @inc_src = map { s/\[\@--/$delimiters{$format}[0]/g;
                       s/--\@\]/$delimiters{$format}[1]/g;
                       $_;
                     } 
                 &$convert_map( $conf->config($inc_file, $agentnum) );

    }

    my $inc_tt = new Text::Template (
      TYPE       => 'ARRAY',
      SOURCE     => [ map "$_\n", @inc_src ],
      DELIMITERS => $delimiters{$format},
    ) or die "Can't create new Text::Template object: $Text::Template::ERROR";

    unless ( $inc_tt->compile() ) {
      my $error = "Can't compile $inc_file template: $Text::Template::ERROR\n";
      warn $error. "Template:\n". join('', map "$_\n", @inc_src);
      die $error;
    }

    $invoice_data{$include} = $inc_tt->fill_in( HASH => \%invoice_data );

    $invoice_data{$include} =~ s/\n+$//
      if ($format eq 'latex');
  }

  $invoice_data{'po_line'} =
    (  $cust_main->payby eq 'BILL' && $cust_main->payinfo )
      ? &$escape_function("Purchase Order #". $cust_main->payinfo)
      : $nbsp;

  my %money_chars = ( 'latex'    => '',
                      'html'     => $conf->config('money_char') || '$',
                      'template' => '',
                    );
  my $money_char = $money_chars{$format};

  my %other_money_chars = ( 'latex'    => '\dollar ',#XXX should be a config too
                            'html'     => $conf->config('money_char') || '$',
                            'template' => '',
                          );
  my $other_money_char = $other_money_chars{$format};
  $invoice_data{'dollar'} = $other_money_char;

  my @detail_items = ();
  my @total_items = ();
  my @buf = ();
  my @sections = ();

  $invoice_data{'detail_items'} = \@detail_items;
  $invoice_data{'total_items'} = \@total_items;
  $invoice_data{'buf'} = \@buf;
  $invoice_data{'sections'} = \@sections;

  my $previous_section = { 'description' => 'Previous Charges',
                           'subtotal'    => $other_money_char.
                                            sprintf('%.2f', $pr_total),
                           'summarized'  => $summarypage ? 'Y' : '',
                         };

  my $taxtotal = 0;
  my $tax_section = { 'description' => 'Taxes, Surcharges, and Fees',
                      'subtotal'    => $taxtotal,   # adjusted below
                      'summarized'  => $summarypage ? 'Y' : '',
                    };
  my $tax_weight = _pkg_category($tax_section->{description})
                        ? _pkg_category($tax_section->{description})->weight
                        : 0;
  $tax_section->{'summarized'} = $summarypage && !$tax_weight ? 'Y' : '';
  $tax_section->{'sort_weight'} = $tax_weight;


  my $adjusttotal = 0;
  my $adjust_section = { 'description' => 'Credits, Payments, and Adjustments',
                         'subtotal'    => 0,   # adjusted below
                         'summarized'  => $summarypage ? 'Y' : '',
                       };
  my $adjust_weight = _pkg_category($adjust_section->{description})
                        ? _pkg_category($adjust_section->{description})->weight
                        : 0;
  $adjust_section->{'summarized'} = $summarypage && !$adjust_weight ? 'Y' : '';
  $adjust_section->{'sort_weight'} = $adjust_weight;

  my $unsquelched = $params{unsquelch_cdr} || $cust_main->squelch_cdr ne 'Y';
  my $multisection = $conf->exists('invoice_sections', $cust_main->agentnum);
  my $late_sections = [];
  my $extra_sections = [];
  my $extra_lines = ();
  if ( $multisection ) {
    ($extra_sections, $extra_lines) =
      $self->_items_extra_usage_sections($escape_function, $format)
      if $conf->exists('usage_class_as_a_section', $cust_main->agentnum);

    push @$extra_sections, $adjust_section if $adjust_section->{sort_weight};

    push @detail_items, @$extra_lines if $extra_lines;
    push @sections,
      $self->_items_sections( $late_sections,      # this could stand a refactor
                              $summarypage,
                              $escape_function,
                              $extra_sections,
                              $format,             #bah
                            );
    if ($conf->exists('svc_phone_sections')) {
      my ($phone_sections, $phone_lines) =
        $self->_items_svc_phone_sections($escape_function, $format);
      push @{$late_sections}, @$phone_sections;
      push @detail_items, @$phone_lines;
    }
  }else{
    push @sections, { 'description' => '', 'subtotal' => '' };
  }

  unless (    $conf->exists('disable_previous_balance')
           || $conf->exists('previous_balance-summary_only')
         )
  {

    foreach my $line_item ( $self->_items_previous ) {

      my $detail = {
        ext_description => [],
      };
      $detail->{'ref'} = $line_item->{'pkgnum'};
      $detail->{'quantity'} = 1;
      $detail->{'section'} = $previous_section;
      $detail->{'description'} = &$escape_function($line_item->{'description'});
      if ( exists $line_item->{'ext_description'} ) {
        @{$detail->{'ext_description'}} = map {
          &$escape_function($_);
        } @{$line_item->{'ext_description'}};
      }
      $detail->{'amount'} = ( $old_latex ? '' : $money_char).
                            $line_item->{'amount'};
      $detail->{'product_code'} = $line_item->{'pkgpart'} || 'N/A';

      push @detail_items, $detail;
      push @buf, [ $detail->{'description'},
                   $money_char. sprintf("%10.2f", $line_item->{'amount'}),
                 ];
    }

  }

  if ( @pr_cust_bill && !$conf->exists('disable_previous_balance') ) {
    push @buf, ['','-----------'];
    push @buf, [ 'Total Previous Balance',
                 $money_char. sprintf("%10.2f", $pr_total) ];
    push @buf, ['',''];
  }

  foreach my $section (@sections, @$late_sections) {

    $invoice_data{finance_amount} = sprintf('%.2f', $section->{'subtotal'} )
      if ( $invoice_data{finance_section} &&
           $section->{'description'} eq $invoice_data{finance_section} );

    $section->{'subtotal'} = $other_money_char.
                             sprintf('%.2f', $section->{'subtotal'})
      if $multisection;

    # begin some normalization
    $section->{'amount'}   = $section->{'subtotal'}
      if $multisection;


    if ( $section->{'description'} ) {
      push @buf, ( [ &$escape_function($section->{'description'}), '' ],
                   [ '', '' ],
                 );
    }

    my %options = ();
    $options{'section'} = $section if $multisection;
    $options{'format'} = $format;
    $options{'escape_function'} = $escape_function;
    $options{'format_function'} = sub { () } unless $unsquelched;
    $options{'unsquelched'} = $unsquelched;
    $options{'summary_page'} = $summarypage;
    $options{'skip_usage'} =
      scalar(@$extra_sections) && !grep{$section == $_} @$extra_sections;

    foreach my $line_item ( $self->_items_pkg(%options) ) {
      my $detail = {
        ext_description => [],
      };
      $detail->{'ref'} = $line_item->{'pkgnum'};
      $detail->{'quantity'} = $line_item->{'quantity'};
      $detail->{'section'} = $section;
      $detail->{'description'} = &$escape_function($line_item->{'description'});
      if ( exists $line_item->{'ext_description'} ) {
        @{$detail->{'ext_description'}} = @{$line_item->{'ext_description'}};
      }
      $detail->{'amount'} = ( $old_latex ? '' : $money_char ).
                              $line_item->{'amount'};
      $detail->{'unit_amount'} = ( $old_latex ? '' : $money_char ).
                                 $line_item->{'unit_amount'};
      $detail->{'product_code'} = $line_item->{'pkgpart'} || 'N/A';
  
      push @detail_items, $detail;
      push @buf, ( [ $detail->{'description'},
                     $money_char. sprintf("%10.2f", $line_item->{'amount'}),
                   ],
                   map { [ " ". $_, '' ] } @{$detail->{'ext_description'}},
                 );
    }

    if ( $section->{'description'} ) {
      push @buf, ( ['','-----------'],
                   [ $section->{'description'}. ' sub-total',
                      $money_char. sprintf("%10.2f", $section->{'subtotal'})
                   ],
                   [ '', '' ],
                   [ '', '' ],
                 );
    }
  
  }
  
  $invoice_data{current_less_finance} =
    sprintf('%.2f', $self->charged - $invoice_data{finance_amount} );

  if ( $multisection && !$conf->exists('disable_previous_balance') ) {
    unshift @sections, $previous_section if $pr_total;
  }

  foreach my $tax ( $self->_items_tax ) {

    $taxtotal += $tax->{'amount'};

    my $description = &$escape_function( $tax->{'description'} );
    my $amount      = sprintf( '%.2f', $tax->{'amount'} );

    if ( $multisection ) {

      my $money = $old_latex ? '' : $money_char;
      push @detail_items, {
        ext_description => [],
        ref          => '',
        quantity     => '',
        description  => $description,
        amount       => $money. $amount,
        product_code => '',
        section      => $tax_section,
      };

    } else {

      push @total_items, {
        'total_item'   => $description,
        'total_amount' => $other_money_char. $amount,
      };

    }

    push @buf,[ $description,
                $money_char. $amount,
              ];

  }
  
  if ( $taxtotal ) {
    my $total = {};
    $total->{'total_item'} = 'Sub-total';
    $total->{'total_amount'} =
      $other_money_char. sprintf('%.2f', $self->charged - $taxtotal );

    if ( $multisection ) {
      $tax_section->{'subtotal'} = $other_money_char.
                                   sprintf('%.2f', $taxtotal);
      $tax_section->{'pretotal'} = 'New charges sub-total '.
                                   $total->{'total_amount'};
      push @sections, $tax_section if $taxtotal;
    }else{
      unshift @total_items, $total;
    }
  }
  $invoice_data{'taxtotal'} = sprintf('%.2f', $taxtotal);

  push @buf,['','-----------'];
  push @buf,[( $conf->exists('disable_previous_balance') 
               ? 'Total Charges'
               : 'Total New Charges'
             ),
             $money_char. sprintf("%10.2f",$self->charged) ];
  push @buf,['',''];

  {
    my $total = {};
    $total->{'total_item'} = &$embolden_function('Total');
    $total->{'total_amount'} =
      &$embolden_function(
        $other_money_char.
        sprintf( '%.2f',
                 $self->charged + ( $conf->exists('disable_previous_balance')
                                    ? 0
                                    : $pr_total
                                  )
               )
      );
    if ( $multisection ) {
      if ( $adjust_section->{'sort_weight'} ) {
        $adjust_section->{'posttotal'} = 'Balance Forward '. $other_money_char.
          sprintf("%.2f", ($self->billing_balance || 0) );
      } else {
        $adjust_section->{'pretotal'} = 'New charges total '. $other_money_char.
                                        sprintf('%.2f', $self->charged );
      } 
    }else{
      push @total_items, $total;
    }
    push @buf,['','-----------'];
    push @buf,['Total Charges',
               $money_char.
               sprintf( '%10.2f', $self->charged +
                                    ( $conf->exists('disable_previous_balance')
                                        ? 0
                                        : $pr_total
                                    )
                      )
              ];
    push @buf,['',''];
  }
  
  unless ( $conf->exists('disable_previous_balance') ) {
    #foreach my $thing ( sort { $a->_date <=> $b->_date } $self->_items_credits, $self->_items_payments
  
    # credits
    my $credittotal = 0;
    foreach my $credit ( $self->_items_credits('trim_len'=>60) ) {

      my $total;
      $total->{'total_item'} = &$escape_function($credit->{'description'});
      $credittotal += $credit->{'amount'};
      $total->{'total_amount'} = '-'. $other_money_char. $credit->{'amount'};
      $adjusttotal += $credit->{'amount'};
      if ( $multisection ) {
        my $money = $old_latex ? '' : $money_char;
        push @detail_items, {
          ext_description => [],
          ref          => '',
          quantity     => '',
          description  => &$escape_function($credit->{'description'}),
          amount       => $money. $credit->{'amount'},
          product_code => '',
          section      => $adjust_section,
        };
      } else {
        push @total_items, $total;
      }

    }
    $invoice_data{'credittotal'} = sprintf('%.2f', $credittotal);

    #credits (again)
    foreach my $credit ( $self->_items_credits('trim_len'=>32) ) {
      push @buf, [ $credit->{'description'}, $money_char.$credit->{'amount'} ];
    }

    # payments
    my $paymenttotal = 0;
    foreach my $payment ( $self->_items_payments ) {
      my $total = {};
      $total->{'total_item'} = &$escape_function($payment->{'description'});
      $paymenttotal += $payment->{'amount'};
      $total->{'total_amount'} = '-'. $other_money_char. $payment->{'amount'};
      $adjusttotal += $payment->{'amount'};
      if ( $multisection ) {
        my $money = $old_latex ? '' : $money_char;
        push @detail_items, {
          ext_description => [],
          ref          => '',
          quantity     => '',
          description  => &$escape_function($payment->{'description'}),
          amount       => $money. $payment->{'amount'},
          product_code => '',
          section      => $adjust_section,
        };
      }else{
        push @total_items, $total;
      }
      push @buf, [ $payment->{'description'},
                   $money_char. sprintf("%10.2f", $payment->{'amount'}),
                 ];
    }
    $invoice_data{'paymenttotal'} = sprintf('%.2f', $paymenttotal);
  
    if ( $multisection ) {
      $adjust_section->{'subtotal'} = $other_money_char.
                                      sprintf('%.2f', $adjusttotal);
      push @sections, $adjust_section
        unless $adjust_section->{sort_weight};
    }

    { 
      my $total;
      $total->{'total_item'} = &$embolden_function($self->balance_due_msg);
      $total->{'total_amount'} =
        &$embolden_function(
          $other_money_char. sprintf('%.2f', $summarypage 
                                               ? $self->charged +
                                                 $self->billing_balance
                                               : $self->owed + $pr_total
                                    )
        );
      if ( $multisection && !$adjust_section->{sort_weight} ) {
        $adjust_section->{'posttotal'} = $total->{'total_item'}. ' '.
                                         $total->{'total_amount'};
      }else{
        push @total_items, $total;
      }
      push @buf,['','-----------'];
      push @buf,[$self->balance_due_msg, $money_char. 
        sprintf("%10.2f", $balance_due ) ];
    }
  }

  if ( $multisection ) {
    if ($conf->exists('svc_phone_sections')) {
      my $total;
      $total->{'total_item'} = &$embolden_function($self->balance_due_msg);
      $total->{'total_amount'} =
        &$embolden_function(
          $other_money_char. sprintf('%.2f', $self->owed + $pr_total)
        );
      my $last_section = pop @sections;
      $last_section->{'posttotal'} = $total->{'total_item'}. ' '.
                                     $total->{'total_amount'};
      push @sections, $last_section;
    }
    push @sections, @$late_sections
      if $unsquelched;
  }

  my @includelist = ();
  push @includelist, 'summary' if $summarypage;
  foreach my $include ( @includelist ) {

    my $inc_file = $conf->key_orbase("invoice_${format}$include", $template);
    my @inc_src;

    if ( length( $conf->config($inc_file, $agentnum) ) ) {

      @inc_src = $conf->config($inc_file, $agentnum);

    } else {

      $inc_file = $conf->key_orbase("invoice_latex$include", $template);

      my $convert_map = $convert_maps{$format}{$include};

      @inc_src = map { s/\[\@--/$delimiters{$format}[0]/g;
                       s/--\@\]/$delimiters{$format}[1]/g;
                       $_;
                     } 
                 &$convert_map( $conf->config($inc_file, $agentnum) );

    }

    my $inc_tt = new Text::Template (
      TYPE       => 'ARRAY',
      SOURCE     => [ map "$_\n", @inc_src ],
      DELIMITERS => $delimiters{$format},
    ) or die "Can't create new Text::Template object: $Text::Template::ERROR";

    unless ( $inc_tt->compile() ) {
      my $error = "Can't compile $inc_file template: $Text::Template::ERROR\n";
      warn $error. "Template:\n". join('', map "$_\n", @inc_src);
      die $error;
    }

    $invoice_data{$include} = $inc_tt->fill_in( HASH => \%invoice_data );

    $invoice_data{$include} =~ s/\n+$//
      if ($format eq 'latex');
  }

  $invoice_lines = 0;
  my $wasfunc = 0;
  foreach ( grep /invoice_lines\(\d*\)/, @invoice_template ) { #kludgy
    /invoice_lines\((\d*)\)/;
    $invoice_lines += $1 || scalar(@buf);
    $wasfunc=1;
  }
  die "no invoice_lines() functions in template?"
    if ( $format eq 'template' && !$wasfunc );

  if ($format eq 'template') {

    if ( $invoice_lines ) {
      $invoice_data{'total_pages'} = int( scalar(@buf) / $invoice_lines );
      $invoice_data{'total_pages'}++
        if scalar(@buf) % $invoice_lines;
    }

    #setup subroutine for the template
    sub FS::cust_bill::_template::invoice_lines {
      my $lines = shift || scalar(@FS::cust_bill::_template::buf);
      map { 
        scalar(@FS::cust_bill::_template::buf)
          ? shift @FS::cust_bill::_template::buf
          : [ '', '' ];
      }
      ( 1 .. $lines );
    }

    my $lines;
    my @collect;
    while (@buf) {
      push @collect, split("\n",
        $text_template->fill_in( HASH => \%invoice_data,
                                 PACKAGE => 'FS::cust_bill::_template'
                               )
      );
      $FS::cust_bill::_template::page++;
    }
    map "$_\n", @collect;
  }else{
    warn "filling in template for invoice ". $self->invnum. "\n"
      if $DEBUG;
    warn join("\n", map " $_ => ". $invoice_data{$_}, keys %invoice_data). "\n"
      if $DEBUG > 1;

    $text_template->fill_in(HASH => \%invoice_data);
  }
}

=item print_ps HASHREF | [ TIME [ , TEMPLATE ] ]

Returns an postscript invoice, as a scalar.

Options can be passed as a hashref (recommended) or as a list of time, template
and then any key/value pairs for any other options.

I<time> an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

sub print_ps {
  my $self = shift;

  my ($file, $lfile) = $self->print_latex(@_);
  my $ps = generate_ps($file);
  unlink($lfile);

  $ps;
}

=item print_pdf HASHREF | [ TIME [ , TEMPLATE ] ]

Returns an PDF invoice, as a scalar.

Options can be passed as a hashref (recommended) or as a list of time, template
and then any key/value pairs for any other options.

I<time> an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

=cut

sub print_pdf {
  my $self = shift;

  my ($file, $lfile) = $self->print_latex(@_);
  my $pdf = generate_pdf($file);
  unlink($lfile);

  $pdf;
}

=item print_html HASHREF | [ TIME [ , TEMPLATE [ , CID ] ] ]

Returns an HTML invoice, as a scalar.

I<time> an optional value used to control the printing of overdue messages.  The
default is now.  It isn't the date of the invoice; that's the `_date' field.
It is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

I<template>, if specified, is the name of a suffix for alternate invoices.

I<notice_name>, if specified, overrides "Invoice" as the name of the sent document (templates from 10/2009 or newer required)

I<cid> is a MIME Content-ID used to create a "cid:" URL for the logo image, used
when emailing the invoice as part of a multipart/related MIME email.

=cut

sub print_html {
  my $self = shift;
  my %params;
  if ( ref($_[0]) ) {
    %params = %{ shift() }; 
  }else{
    $params{'time'} = shift;
    $params{'template'} = shift;
    $params{'cid'} = shift;
  }

  $params{'format'} = 'html';

  $self->print_generic( %params );
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

sub _translate_old_latex_format {
  warn "_translate_old_latex_format called\n"
    if $DEBUG; 

  my @template = ();
  while ( @_ ) {
    my $line = shift;
  
    if ( $line =~ /^%%Detail\s*$/ ) {
  
      push @template, q![@--!,
                      q!  foreach my $_tr_line (@detail_items) {!,
                      q!    if ( scalar ($_tr_item->{'ext_description'} ) ) {!,
                      q!      $_tr_line->{'description'} .= !, 
                      q!        "\\tabularnewline\n~~".!,
                      q!        join( "\\tabularnewline\n~~",!,
                      q!          @{$_tr_line->{'ext_description'}}!,
                      q!        );!,
                      q!    }!;

      while ( ( my $line_item_line = shift )
              !~ /^%%EndDetail\s*$/                            ) {
        $line_item_line =~ s/'/\\'/g;    # nice LTS
        $line_item_line =~ s/\\/\\\\/g;  # escape quotes and backslashes
        $line_item_line =~ s/\$(\w+)/'. \$_tr_line->{$1}. '/g;
        push @template, "    \$OUT .= '$line_item_line';";
      }

      push @template, '}',
                      '--@]';
      #' doh, gvim
    } elsif ( $line =~ /^%%TotalDetails\s*$/ ) {

      push @template, '[@--',
                      '  foreach my $_tr_line (@total_items) {';

      while ( ( my $total_item_line = shift )
              !~ /^%%EndTotalDetails\s*$/                      ) {
        $total_item_line =~ s/'/\\'/g;    # nice LTS
        $total_item_line =~ s/\\/\\\\/g;  # escape quotes and backslashes
        $total_item_line =~ s/\$(\w+)/'. \$_tr_line->{$1}. '/g;
        push @template, "    \$OUT .= '$total_item_line';";
      }

      push @template, '}',
                      '--@]';

    } else {
      $line =~ s/\$(\w+)/[\@-- \$$1 --\@]/g;
      push @template, $line;  
    }
  
  }

  if ($DEBUG) {
    warn "$_\n" foreach @template;
  }

  (@template);
}

sub terms {
  my $self = shift;

  #check for an invoice-specific override
  return $self->invoice_terms if $self->invoice_terms;
  
  #check for a customer- specific override
  my $cust_main = $self->cust_main;
  return $cust_main->invoice_terms if $cust_main->invoice_terms;

  #use configured default
  $conf->config('invoice_default_terms') || '';
}

sub due_date {
  my $self = shift;
  my $duedate = '';
  if ( $self->terms =~ /^\s*Net\s*(\d+)\s*$/ ) {
    $duedate = $self->_date() + ( $1 * 86400 );
  }
  $duedate;
}

sub due_date2str {
  my $self = shift;
  $self->due_date ? time2str(shift, $self->due_date) : '';
}

sub balance_due_msg {
  my $self = shift;
  my $msg = 'Balance Due';
  return $msg unless $self->terms;
  if ( $self->due_date ) {
    $msg .= ' - Please pay by '. $self->due_date2str('%x');
  } elsif ( $self->terms ) {
    $msg .= ' - '. $self->terms;
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
  'Invoice #'. $self->invnum. ' ('. $self->_date_pretty. ')';
}

=item _date_pretty

Returns a string with the date, for example: "3/20/2008"

=cut

sub _date_pretty {
  my $self = shift;
  time2str('%x', $self->_date);
}

use vars qw(%pkg_category_cache);
sub _items_sections {
  my $self = shift;
  my $late = shift;
  my $summarypage = shift;
  my $escape = shift;
  my $extra_sections = shift;
  my $format = shift;

  my %subtotal = ();
  my %late_subtotal = ();
  my %not_tax = ();

  foreach my $cust_bill_pkg ( $self->cust_bill_pkg )
  {

      my $usage = $cust_bill_pkg->usage;

      foreach my $display ($cust_bill_pkg->cust_bill_pkg_display) {
        next if ( $display->summary && $summarypage );

        my $section = $display->section;
        my $type    = $display->type;

        $not_tax{$section} = 1
          unless $cust_bill_pkg->pkgnum == 0;

        if ( $display->post_total && !$summarypage ) {
          if (! $type || $type eq 'S') {
            $late_subtotal{$section} += $cust_bill_pkg->setup
              if $cust_bill_pkg->setup != 0;
          }

          if (! $type) {
            $late_subtotal{$section} += $cust_bill_pkg->recur
              if $cust_bill_pkg->recur != 0;
          }

          if ($type && $type eq 'R') {
            $late_subtotal{$section} += $cust_bill_pkg->recur - $usage
              if $cust_bill_pkg->recur != 0;
          }
          
          if ($type && $type eq 'U') {
            $late_subtotal{$section} += $usage
              unless scalar(@$extra_sections);
          }

        } else {

          next if $cust_bill_pkg->pkgnum == 0 && ! $section;

          if (! $type || $type eq 'S') {
            $subtotal{$section} += $cust_bill_pkg->setup
              if $cust_bill_pkg->setup != 0;
          }

          if (! $type) {
            $subtotal{$section} += $cust_bill_pkg->recur
              if $cust_bill_pkg->recur != 0;
          }

          if ($type && $type eq 'R') {
            $subtotal{$section} += $cust_bill_pkg->recur - $usage
              if $cust_bill_pkg->recur != 0;
          }
          
          if ($type && $type eq 'U') {
            $subtotal{$section} += $usage
              unless scalar(@$extra_sections);
          }

        }

      }

  }

  %pkg_category_cache = ();

  push @$late, map { { 'description' => &{$escape}($_),
                       'subtotal'    => $late_subtotal{$_},
                       'post_total'  => 1,
                       'sort_weight' => ( _pkg_category($_)
                                            ? _pkg_category($_)->weight
                                            : 0
                                       ),
                       ((_pkg_category($_) && _pkg_category($_)->condense)
                                           ? $self->_condense_section($format)
                                           : ()
                       ),
                   } }
                 sort _sectionsort keys %late_subtotal;

  my @sections;
  if ( $summarypage ) {
    @sections = grep { exists($subtotal{$_}) || ! _pkg_category($_)->disabled }
                map { $_->categoryname } qsearch('pkg_category', {});
  } else {
    @sections = keys %subtotal;
  }

  my @early = map { { 'description' => &{$escape}($_),
                      'subtotal'    => $subtotal{$_},
                      'summarized'  => $not_tax{$_} ? '' : 'Y',
                      'tax_section' => $not_tax{$_} ? '' : 'Y',
                      'sort_weight' => ( _pkg_category($_)
                                           ? _pkg_category($_)->weight
                                           : 0
                                       ),
                       ((_pkg_category($_) && _pkg_category($_)->condense)
                                           ? $self->_condense_section($format)
                                           : ()
                       ),
                    }
                  } @sections;
  push @early, @$extra_sections if $extra_sections;
 
  sort { $a->{sort_weight} <=> $b->{sort_weight} } @early;

}

#helper subs for above

sub _sectionsort {
  _pkg_category($a)->weight <=> _pkg_category($b)->weight;
}

sub _pkg_category {
  my $categoryname = shift;
  $pkg_category_cache{$categoryname} ||=
    qsearchs( 'pkg_category', { 'categoryname' => $categoryname } );
}

my %condensed_format = (
  'label' => [ qw( Description Qty Amount ) ],
  'fields' => [
                sub { shift->{description} },
                sub { shift->{quantity} },
                sub { shift->{amount} },
              ],
  'align'  => [ qw( l r r ) ],
  'span'   => [ qw( 5 1 1 ) ],            # unitprices?
  'width'  => [ qw( 10.7cm 1.4cm 1.6cm ) ],   # don't like this
);

sub _condense_section {
  my ( $self, $format ) = ( shift, shift );
  ( 'condensed' => 1,
    map { my $method = "_condensed_$_"; $_ => $self->$method($format) }
      qw( description_generator
          header_generator
          total_generator
          total_line_generator
        )
  );
}

sub _condensed_generator_defaults {
  my ( $self, $format ) = ( shift, shift );
  return ( \%condensed_format, ' ', ' ', ' ', sub { shift } );
}

my %html_align = (
  'c' => 'center',
  'l' => 'left',
  'r' => 'right',
);

sub _condensed_header_generator {
  my ( $self, $format ) = ( shift, shift );

  my ( $f, $prefix, $suffix, $separator, $column ) =
    _condensed_generator_defaults($format);

  if ($format eq 'latex') {
    $prefix = "\\hline\n\\rule{0pt}{2.5ex}\n\\makebox[1.4cm]{}&\n";
    $suffix = "\\\\\n\\hline";
    $separator = "&\n";
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return "\\multicolumn{$s}{$a}{\\makebox[$w][$a]{\\textbf{$d}}}";
          };
  } elsif ( $format eq 'html' ) {
    $prefix = '<th></th>';
    $suffix = '';
    $separator = '';
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return qq!<th align="$html_align{$a}">$d</th>!;
      };
  }

  sub {
    my @args = @_;
    my @result = ();

    foreach  (my $i = 0; $f->{label}->[$i]; $i++) {
      push @result,
        &{$column}( map { $f->{$_}->[$i] } qw(label align span width) );
    }

    $prefix. join($separator, @result). $suffix;
  };

}

sub _condensed_description_generator {
  my ( $self, $format ) = ( shift, shift );

  my ( $f, $prefix, $suffix, $separator, $column ) =
    _condensed_generator_defaults($format);

  if ($format eq 'latex') {
    $prefix = "\\hline\n\\multicolumn{1}{c}{\\rule{0pt}{2.5ex}~} &\n";
    $suffix = '\\\\';
    $separator = " & \n";
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return "\\multicolumn{$s}{$a}{\\makebox[$w][$a]{\\textbf{$d}}}";
          };
  }elsif ( $format eq 'html' ) {
    $prefix = '"><td align="center"></td>';
    $suffix = '';
    $separator = '';
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return qq!<td align="$html_align{$a}">$d</td>!;
      };
  }

  sub {
    my @args = @_;
    my @result = ();

    foreach  (my $i = 0; $f->{label}->[$i]; $i++) {
      push @result, &{$column}( &{$f->{fields}->[$i]}(@args),
                                map { $f->{$_}->[$i] } qw(align span width)
                              );
    }

    $prefix. join( $separator, @result ). $suffix;
  };

}

sub _condensed_total_generator {
  my ( $self, $format ) = ( shift, shift );

  my ( $f, $prefix, $suffix, $separator, $column ) =
    _condensed_generator_defaults($format);
  my $style = '';

  if ($format eq 'latex') {
    $prefix = "& ";
    $suffix = "\\\\\n";
    $separator = " & \n";
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return "\\multicolumn{$s}{$a}{\\makebox[$w][$a]{$d}}";
          };
  }elsif ( $format eq 'html' ) {
    $prefix = '';
    $suffix = '';
    $separator = '';
    $style = 'border-top: 3px solid #000000;border-bottom: 3px solid #000000;';
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return qq!<td align="$html_align{$a}" style="$style">$d</td>!;
      };
  }


  sub {
    my @args = @_;
    my @result = ();

    #  my $r = &{$f->{fields}->[$i]}(@args);
    #  $r .= ' Total' unless $i;

    foreach  (my $i = 0; $f->{label}->[$i]; $i++) {
      push @result,
        &{$column}( &{$f->{fields}->[$i]}(@args). ($i ? '' : ' Total'),
                    map { $f->{$_}->[$i] } qw(align span width)
                  );
    }

    $prefix. join( $separator, @result ). $suffix;
  };

}

=item total_line_generator FORMAT

Returns a coderef used for generation of invoice total line items for this
usage_class.  FORMAT is either html or latex

=cut

# should not be used: will have issues with hash element names (description vs
# total_item and amount vs total_amount -- another array of functions?

sub _condensed_total_line_generator {
  my ( $self, $format ) = ( shift, shift );

  my ( $f, $prefix, $suffix, $separator, $column ) =
    _condensed_generator_defaults($format);
  my $style = '';

  if ($format eq 'latex') {
    $prefix = "& ";
    $suffix = "\\\\\n";
    $separator = " & \n";
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return "\\multicolumn{$s}{$a}{\\makebox[$w][$a]{$d}}";
          };
  }elsif ( $format eq 'html' ) {
    $prefix = '';
    $suffix = '';
    $separator = '';
    $style = 'border-top: 3px solid #000000;border-bottom: 3px solid #000000;';
    $column =
      sub { my ($d,$a,$s,$w) = @_;
            return qq!<td align="$html_align{$a}" style="$style">$d</td>!;
      };
  }


  sub {
    my @args = @_;
    my @result = ();

    foreach  (my $i = 0; $f->{label}->[$i]; $i++) {
      push @result,
        &{$column}( &{$f->{fields}->[$i]}(@args),
                    map { $f->{$_}->[$i] } qw(align span width)
                  );
    }

    $prefix. join( $separator, @result ). $suffix;
  };

}

#sub _items_extra_usage_sections {
#  my $self = shift;
#  my $escape = shift;
#
#  my %sections = ();
#
#  my %usage_class =  map{ $_->classname, $_ } qsearch('usage_class', {});
#  foreach my $cust_bill_pkg ( $self->cust_bill_pkg )
#  {
#    next unless $cust_bill_pkg->pkgnum > 0;
#
#    foreach my $section ( keys %usage_class ) {
#
#      my $usage = $cust_bill_pkg->usage($section);
#
#      next unless $usage && $usage > 0;
#
#      $sections{$section} ||= 0;
#      $sections{$section} += $usage;
#
#    }
#
#  }
#
#  map { { 'description' => &{$escape}($_),
#          'subtotal'    => $sections{$_},
#          'summarized'  => '',
#          'tax_section' => '',
#        }
#      }
#    sort {$usage_class{$a}->weight <=> $usage_class{$b}->weight} keys %sections;
#
#}

sub _items_extra_usage_sections {
  my $self = shift;
  my $escape = shift;
  my $format = shift;

  my %sections = ();
  my %classnums = ();
  my %lines = ();

  my %usage_class =  map { $_->classnum => $_ } qsearch( 'usage_class', {} );
  foreach my $cust_bill_pkg ( $self->cust_bill_pkg ) {
    next unless $cust_bill_pkg->pkgnum > 0;

    foreach my $classnum ( keys %usage_class ) {
      my $section = $usage_class{$classnum}->classname;
      $classnums{$section} = $classnum;

      foreach my $detail ( $cust_bill_pkg->cust_bill_pkg_detail($classnum) ) {
        my $amount = $detail->amount;
        next unless $amount && $amount > 0;
 
        $sections{$section} ||= { 'subtotal'=>0, 'calls'=>0, 'duration'=>0 };
        $sections{$section}{amount} += $amount;  #subtotal
        $sections{$section}{calls}++;
        $sections{$section}{duration} += $detail->duration;

        my $desc = $detail->regionname; 
        my $description = $desc;
        $description = substr($desc, 0, 50). '...'
          if $format eq 'latex' && length($desc) > 50;

        $lines{$section}{$desc} ||= {
          description     => &{$escape}($description),
          #pkgpart         => $part_pkg->pkgpart,
          pkgnum          => $cust_bill_pkg->pkgnum,
          ref             => '',
          amount          => 0,
          calls           => 0,
          duration        => 0,
          #unit_amount     => $cust_bill_pkg->unitrecur,
          quantity        => $cust_bill_pkg->quantity,
          product_code    => 'N/A',
          ext_description => [],
        };

        $lines{$section}{$desc}{amount} += $amount;
        $lines{$section}{$desc}{calls}++;
        $lines{$section}{$desc}{duration} += $detail->duration;

      }
    }
  }

  my %sectionmap = ();
  foreach (keys %sections) {
    my $usage_class = $usage_class{$classnums{$_}};
    $sectionmap{$_} = { 'description' => &{$escape}($_),
                        'amount'    => $sections{$_}{amount},    #subtotal
                        'calls'       => $sections{$_}{calls},
                        'duration'    => $sections{$_}{duration},
                        'summarized'  => '',
                        'tax_section' => '',
                        'sort_weight' => $usage_class->weight,
                        ( $usage_class->format
                          ? ( map { $_ => $usage_class->$_($format) }
                              qw( description_generator header_generator total_generator total_line_generator )
                            )
                          : ()
                        ), 
                      };
  }

  my @sections = sort { $a->{sort_weight} <=> $b->{sort_weight} }
                 values %sectionmap;

  my @lines = ();
  foreach my $section ( keys %lines ) {
    foreach my $line ( keys %{$lines{$section}} ) {
      my $l = $lines{$section}{$line};
      $l->{section}     = $sectionmap{$section};
      $l->{amount}      = sprintf( "%.2f", $l->{amount} );
      #$l->{unit_amount} = sprintf( "%.2f", $l->{unit_amount} );
      push @lines, $l;
    }
  }

  return(\@sections, \@lines);

}

sub _items_svc_phone_sections {
  my $self = shift;
  my $escape = shift;
  my $format = shift;

  my %sections = ();
  my %classnums = ();
  my %lines = ();

  my %usage_class =  map { $_->classnum => $_ } qsearch( 'usage_class', {} );

  foreach my $cust_bill_pkg ( $self->cust_bill_pkg ) {
    next unless $cust_bill_pkg->pkgnum > 0;

    foreach my $detail ( $cust_bill_pkg->cust_bill_pkg_detail ) {

      my $phonenum = $detail->phonenum;
      next unless $phonenum;

      my $amount = $detail->amount;
      next unless $amount && $amount > 0;

      $sections{$phonenum} ||= { 'amount'      => 0,
                                 'calls'       => 0,
                                 'duration'    => 0,
                                 'sort_weight' => -1,
                                 'phonenum'    => $phonenum,
                                };
      $sections{$phonenum}{amount} += $amount;  #subtotal
      $sections{$phonenum}{calls}++;
      $sections{$phonenum}{duration} += $detail->duration;

      my $desc = $detail->regionname; 
      my $description = $desc;
      $description = substr($desc, 0, 50). '...'
        if $format eq 'latex' && length($desc) > 50;

      $lines{$phonenum}{$desc} ||= {
        description     => &{$escape}($description),
        #pkgpart         => $part_pkg->pkgpart,
        pkgnum          => '',
        ref             => '',
        amount          => 0,
        calls           => 0,
        duration        => 0,
        #unit_amount     => '',
        quantity        => '',
        product_code    => 'N/A',
        ext_description => [],
      };

      $lines{$phonenum}{$desc}{amount} += $amount;
      $lines{$phonenum}{$desc}{calls}++;
      $lines{$phonenum}{$desc}{duration} += $detail->duration;

      my $line = $usage_class{$detail->classnum}->classname;
      $sections{"$phonenum $line"} ||=
        { 'amount' => 0,
          'calls' => 0,
          'duration' => 0,
          'sort_weight' => $usage_class{$detail->classnum}->weight,
          'phonenum' => $phonenum,
        };
      $sections{"$phonenum $line"}{amount} += $amount;  #subtotal
      $sections{"$phonenum $line"}{calls}++;
      $sections{"$phonenum $line"}{duration} += $detail->duration;

      $lines{"$phonenum $line"}{$desc} ||= {
        description     => &{$escape}($description),
        #pkgpart         => $part_pkg->pkgpart,
        pkgnum          => '',
        ref             => '',
        amount          => 0,
        calls           => 0,
        duration        => 0,
        #unit_amount     => '',
        quantity        => '',
        product_code    => 'N/A',
        ext_description => [],
      };

      $lines{"$phonenum $line"}{$desc}{amount} += $amount;
      $lines{"$phonenum $line"}{$desc}{calls}++;
      $lines{"$phonenum $line"}{$desc}{duration} += $detail->duration;
      push @{$lines{"$phonenum $line"}{$desc}{ext_description}},
           $detail->formatted('format' => $format);

    }
  }

  my %sectionmap = ();
  my $simple = new FS::usage_class { format => 'simple' }; #bleh
  my $usage_simple = new FS::usage_class { format => 'usage_simple' }; #bleh
  foreach ( keys %sections ) {
    my $summary = $sections{$_}{sort_weight} < 0 ? 1 : 0;
    my $usage_class = $summary ? $simple : $usage_simple;
    my $ending = $summary ? ' usage charges' : '';
    $sectionmap{$_} = { 'description' => &{$escape}($_. $ending),
                        'amount'    => $sections{$_}{amount},    #subtotal
                        'calls'       => $sections{$_}{calls},
                        'duration'    => $sections{$_}{duration},
                        'summarized'  => '',
                        'tax_section' => '',
                        'phonenum'    => $sections{$_}{phonenum},
                        'sort_weight' => $sections{$_}{sort_weight},
                        'post_total'  => $summary, #inspire pagebreak
                        (
                          ( map { $_ => $usage_class->$_($format) }
                            qw( description_generator
                                header_generator
                                total_generator
                                total_line_generator
                              )
                          )
                        ), 
                      };
  }

  my @sections = sort { $a->{phonenum} cmp $b->{phonenum} ||
                        $a->{sort_weight} <=> $b->{sort_weight}
                      }
                 values %sectionmap;

  my @lines = ();
  foreach my $section ( keys %lines ) {
    foreach my $line ( keys %{$lines{$section}} ) {
      my $l = $lines{$section}{$line};
      $l->{section}     = $sectionmap{$section};
      $l->{amount}      = sprintf( "%.2f", $l->{amount} );
      #$l->{unit_amount} = sprintf( "%.2f", $l->{unit_amount} );
      push @lines, $l;
    }
  }

  return(\@sections, \@lines);

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
  my %options = @_;
  my @cust_bill_pkg = grep { $_->pkgnum } $self->cust_bill_pkg;
  my @items = $self->_items_cust_bill_pkg(\@cust_bill_pkg, @_);
  if ($options{section} && $options{section}->{condensed}) {
    my %itemshash = ();
    local $Storable::canonical = 1;
    foreach ( @items ) {
      my $item = { %$_ };
      delete $item->{ref};
      delete $item->{ext_description};
      my $key = freeze($item);
      $itemshash{$key} ||= 0;
      $itemshash{$key} ++; # += $item->{quantity};
    }
    @items = sort { $a->{description} cmp $b->{description} }
             map { my $i = thaw($_);
                   $i->{quantity} = $itemshash{$_};
                   $i->{amount} =
                     sprintf( "%.2f", $i->{quantity} * $i->{amount} );#unit_amount
                   $i;
                 }
             keys %itemshash;
  }
  @items;
}

sub _taxsort {
  return 0 unless $a cmp $b;
  return -1 if $b eq 'Tax';
  return 1 if $a eq 'Tax';
  return -1 if $b eq 'Other surcharges';
  return 1 if $a eq 'Other surcharges';
  $a cmp $b;
}

sub _items_tax {
  my $self = shift;
  my @cust_bill_pkg = sort _taxsort grep { ! $_->pkgnum } $self->cust_bill_pkg;
  $self->_items_cust_bill_pkg(\@cust_bill_pkg, @_);
}

sub _items_cust_bill_pkg {
  my $self = shift;
  my $cust_bill_pkg = shift;
  my %opt = @_;

  my $format = $opt{format} || '';
  my $escape_function = $opt{escape_function} || sub { shift };
  my $format_function = $opt{format_function} || '';
  my $unsquelched = $opt{unsquelched} || '';
  my $section = $opt{section}->{description} if $opt{section};
  my $summary_page = $opt{summary_page} || '';

  my @b = ();
  my ($s, $r, $u) = ( undef, undef, undef );
  foreach my $cust_bill_pkg ( @$cust_bill_pkg )
  {

    foreach ( $s, $r, ($opt{skip_usage} ? $u : () ) ) {
      if ( $_ && !$cust_bill_pkg->hidden ) {
        $_->{amount}      = sprintf( "%.2f", $_->{amount} ),
        $_->{amount}      =~ s/^\-0\.00$/0.00/;
        $_->{unit_amount} = sprintf( "%.2f", $_->{unit_amount} ),
        push @b, { %$_ }
          unless $_->{amount} == 0;
        $_ = undef;
      }
    }

    foreach my $display ( grep { defined($section)
                                 ? $_->section eq $section
                                 : 1
                               }
                          grep { !$_->summary || !$summary_page }
                          $cust_bill_pkg->cust_bill_pkg_display
                        )
    {

      my $type = $display->type;

      my $desc = $cust_bill_pkg->desc;
      $desc = substr($desc, 0, 50). '...'
        if $format eq 'latex' && length($desc) > 50;

      my %details_opt = ( 'format'          => $format,
                          'escape_function' => $escape_function,
                          'format_function' => $format_function,
                        );

      if ( $cust_bill_pkg->pkgnum > 0 ) {

        my $cust_pkg = $cust_bill_pkg->cust_pkg;

        if ( $cust_bill_pkg->setup != 0 && (!$type || $type eq 'S') ) {

          my $description = $desc;
          $description .= ' Setup' if $cust_bill_pkg->recur != 0;

          my @d = ();
          push @d, map &{$escape_function}($_),
                       $cust_pkg->h_labels_short($self->_date)
            unless $cust_pkg->part_pkg->hide_svc_detail
                || $cust_bill_pkg->hidden;
          push @d, $cust_bill_pkg->details(%details_opt)
            if $cust_bill_pkg->recur == 0;

          if ( $cust_bill_pkg->hidden ) {
            $s->{amount}      += $cust_bill_pkg->setup;
            $s->{unit_amount} += $cust_bill_pkg->unitsetup;
            push @{ $s->{ext_description} }, @d;
          } else {
            $s = {
              description     => $description,
              #pkgpart         => $part_pkg->pkgpart,
              pkgnum          => $cust_bill_pkg->pkgnum,
              amount          => $cust_bill_pkg->setup,
              unit_amount     => $cust_bill_pkg->unitsetup,
              quantity        => $cust_bill_pkg->quantity,
              ext_description => \@d,
            };
          };

        }

        if ( $cust_bill_pkg->recur != 0 &&
             ( !$type || $type eq 'R' || $type eq 'U' )
           )
        {

          my $is_summary = $display->summary;
          my $description = ($is_summary && $type && $type eq 'U')
                            ? "Usage charges" : $desc;

          unless ( $conf->exists('disable_line_item_date_ranges') ) {
            $description .= " (" . time2str("%x", $cust_bill_pkg->sdate).
                            " - ". time2str("%x", $cust_bill_pkg->edate). ")";
          }

          my @d = ();

          #at least until cust_bill_pkg has "past" ranges in addition to
          #the "future" sdate/edate ones... see #3032
          my @dates = ( $self->_date );
          my $prev = $cust_bill_pkg->previous_cust_bill_pkg;
          push @dates, $prev->sdate if $prev;

          push @d, map &{$escape_function}($_),
                       $cust_pkg->h_labels_short(@dates)
                                                 #$cust_bill_pkg->edate,
                                                 #$cust_bill_pkg->sdate)
            unless $cust_pkg->part_pkg->hide_svc_detail
                || $cust_bill_pkg->itemdesc
                || $cust_bill_pkg->hidden
                || $is_summary && $type && $type eq 'U';

          push @d, $cust_bill_pkg->details(%details_opt)
            unless ($is_summary || $type && $type eq 'R');
  
          my $amount = 0;
          if (!$type) {
            $amount = $cust_bill_pkg->recur;
          }elsif($type eq 'R') {
            $amount = $cust_bill_pkg->recur - $cust_bill_pkg->usage;
          }elsif($type eq 'U') {
            $amount = $cust_bill_pkg->usage;
          }
  
          if ( !$type || $type eq 'R' ) {

            if ( $cust_bill_pkg->hidden ) {
              $r->{amount}      += $amount;
              $r->{unit_amount} += $cust_bill_pkg->unitrecur;
              push @{ $r->{ext_description} }, @d;
            } else {
              $r = {
                description     => $description,
                #pkgpart         => $part_pkg->pkgpart,
                pkgnum          => $cust_bill_pkg->pkgnum,
                amount          => $amount,
                unit_amount     => $cust_bill_pkg->unitrecur,
                quantity        => $cust_bill_pkg->quantity,
                ext_description => \@d,
              };
            }

          } elsif ( $amount ) {  # && $type eq 'U'

            if ( $cust_bill_pkg->hidden ) {
              $u->{amount}      += $amount;
              $u->{unit_amount} += $cust_bill_pkg->unitrecur;
              push @{ $u->{ext_description} }, @d;
            } else {
              $u = {
                description     => $description,
                #pkgpart         => $part_pkg->pkgpart,
                pkgnum          => $cust_bill_pkg->pkgnum,
                amount          => $amount,
                unit_amount     => $cust_bill_pkg->unitrecur,
                quantity        => $cust_bill_pkg->quantity,
                ext_description => \@d,
              };
            }

          }

        } # recurring or usage with recurring charge

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

  }

  foreach ( $s, $r, ($opt{skip_usage} ? $u : () ) ) {
    if ( $_  ) {
      $_->{amount}      = sprintf( "%.2f", $_->{amount} ),
      $_->{amount}      =~ s/^\-0\.00$/0.00/;
      $_->{unit_amount} = sprintf( "%.2f", $_->{unit_amount} ),
      push @b, { %$_ }
        unless $_->{amount} == 0;
    }
  }

  @b;

}

sub _items_credits {
  my( $self, %opt ) = @_;
  my $trim_len = $opt{'trim_len'} || 60;

  my @b;
  #credits
  foreach ( $self->cust_credited ) {

    #something more elaborate if $_->amount ne $_->cust_credit->credited ?

    my $reason = substr($_->cust_credit->reason, 0, $trim_len);
    $reason .= '...' if length($reason) < length($_->cust_credit->reason);
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

=item call_details [ OPTION => VALUE ... ]

Returns an array of CSV strings representing the call details for this invoice
The only option available is the boolean prepend_billed_number

=cut

sub call_details {
  my ($self, %opt) = @_;

  my $format_function = sub { shift };

  if ($opt{prepend_billed_number}) {
    $format_function = sub {
      my $detail = shift;
      my $row = shift;

      $row->amount ? $row->phonenum. ",". $detail : '"Billed number",'. $detail;
      
    };
  }

  my @details = map { $_->details( 'format_function' => $format_function,
                                   'escape_function' => sub{ return() },
                                 )
                    }
                  grep { $_->pkgnum }
                  $self->cust_bill_pkg;
  my $header = $details[0];
  ( $header, grep { $_ ne $header } @details );
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

  my $extra_sql = ' WHERE '. FS::cust_bill->search_sql_where(\%param);

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

=item search_sql_where HASHREF

Class method which returns an SQL WHERE fragment to search for parameters
specified in HASHREF.  Valid parameters are

=over 4

=item _date

List reference of start date, end date, as UNIX timestamps.

=item invnum_min

=item invnum_max

=item agentnum

=item charged

List reference of charged limits (exclusive).

=item owed

List reference of charged limits (exclusive).

=item open

flag, return open invoices only

=item net

flag, return net invoices only

=item days

=item newest_percust

=back

Note: validates all passed-in data; i.e. safe to use with unchecked CGI params.

=cut

sub search_sql_where {
  my($class, $param) = @_;
  if ( $DEBUG ) {
    warn "$me search_sql_where called with params: \n".
         join("\n", map { "  $_: ". $param->{$_} } keys %$param ). "\n";
  }

  my @search = ();

  #agentnum
  if ( $param->{'agentnum'} =~ /^(\d+)$/ ) {
    push @search, "cust_main.agentnum = $1";
  }

  #_date
  if ( $param->{_date} ) {
    my($beginning, $ending) = @{$param->{_date}};

    push @search, "cust_bill._date >= $beginning",
                  "cust_bill._date <  $ending";
  }

  #invnum
  if ( $param->{'invnum_min'} =~ /^(\d+)$/ ) {
    push @search, "cust_bill.invnum >= $1";
  }
  if ( $param->{'invnum_max'} =~ /^(\d+)$/ ) {
    push @search, "cust_bill.invnum <= $1";
  }

  #charged
  if ( $param->{charged} ) {
    my @charged = ref($param->{charged})
                    ? @{ $param->{charged} }
                    : ($param->{charged});

    push @search, map { s/^charged/cust_bill.charged/; $_; }
                      @charged;
  }

  my $owed_sql = FS::cust_bill->owed_sql;

  #owed
  if ( $param->{owed} ) {
    my @owed = ref($param->{owed})
                 ? @{ $param->{owed} }
                 : ($param->{owed});
    push @search, map { s/^owed/$owed_sql/; $_; }
                      @owed;
  }

  #open/net flags
  push @search, "0 != $owed_sql"
    if $param->{'open'};
  push @search, '0 != '. FS::cust_bill->net_sql
    if $param->{'net'};

  #days
  push @search, "cust_bill._date < ". (time-86400*$param->{'days'})
    if $param->{'days'};

  #newest_percust
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

  #agent virtualization
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

