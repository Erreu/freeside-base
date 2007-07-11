<% include( '/elements/header.html', ucfirst($type{$payby}). ' processing successful',
             include('/elements/menubar.html'),

    )
%>
<% include( '/elements/small_custview.html', $cust_main, '', '', popurl(3). "view/cust_main.cgi" ) %>

<% include('/elements/footer.html') %>
<%init>

#some false laziness w/MyAccount::process_payment

$cgi->param('custnum') =~ /^(\d+)$/
  or die "illegal custnum ". $cgi->param('custnum');
my $custnum = $1;

my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } );
die "unknown custnum $custnum" unless $cust_main;

$cgi->param('amount') =~ /^\s*(\d*(\.\d\d)?)\s*$/
  or eidiot "illegal amount ". $cgi->param('amount');
my $amount = $1;
eidiot "amount <= 0" unless $amount > 0;

$cgi->param('year') =~ /^(\d+)$/
  or die "illegal year ". $cgi->param('year');
my $year = $1;

$cgi->param('month') =~ /^(\d+)$/
  or die "illegal month ". $cgi->param('month');
my $month = $1;

$cgi->param('payby') =~ /^(CARD|CHEK)$/
  or die "illegal payby ". $cgi->param('payby');
my $payby = $1;
my %payby2fields = (
  'CARD' => [ qw( address1 address2 city state zip ) ],
  'CHEK' => [ qw( ss paytype paystate stateid stateid_state ) ],
);
my %type = ( 'CARD' => 'credit card',
             'CHEK' => 'electronic check (ACH)',
           );

$cgi->param('payname') =~ /^([\w \,\.\-\']+)$/
  or eidiot gettext('illegal_name'). " payname: ". $cgi->param('payname');
my $payname = $1;

$cgi->param('payunique') =~ /^([\w \!\@\#\$\%\&\(\)\-\+\;\:\'\"\,\.\?\/\=]*)$/
  or eidiot gettext('illegal_text'). " payunique: ". $cgi->param('payunique');
my $payunique = $1;

my $payinfo;
my $paycvv = '';
if ( $payby eq 'CHEK' ) {

  if ($cgi->param('payinfo1') =~ /xx/i || $cgi->param('payinfo2') =~ /xx/i ) {
    $payinfo = $cust_main->payinfo;
  } else {
    $cgi->param('payinfo1') =~ /^(\d+)$/
      or eidiot "illegal account number ". $cgi->param('payinfo1');
    my $payinfo1 = $1;
    $cgi->param('payinfo2') =~ /^(\d+)$/
      or eidiot "illegal ABA/routing number ". $cgi->param('payinfo2');
    my $payinfo2 = $1;
    $payinfo = $payinfo1. '@'. $payinfo2;
  }

} elsif ( $payby eq 'CARD' ) {

  $payinfo = $cgi->param('payinfo');
  if ($payinfo eq $cust_main->paymask) {
    $payinfo = $cust_main->payinfo;
  }
  $payinfo =~ s/\D//g;
  $payinfo =~ /^(\d{13,16})$/
    or eidiot gettext('invalid_card'); # . ": ". $self->payinfo;
  $payinfo = $1;
  validate($payinfo)
    or eidiot gettext('invalid_card'); # . ": ". $self->payinfo;
  eidiot gettext('unknown_card_type')
    if cardtype($payinfo) eq "Unknown";

  if ( defined $cust_main->dbdef_table->column('paycvv') ) {
    if ( length($cgi->param('paycvv') ) ) {
      if ( cardtype($payinfo) eq 'American Express card' ) {
        $cgi->param('paycvv') =~ /^(\d{4})$/
          or eidiot "CVV2 (CID) for American Express cards is four digits.";
        $paycvv = $1;
      } else {
        $cgi->param('paycvv') =~ /^(\d{3})$/
          or eidiot "CVV2 (CVC2/CID) is three digits.";
        $paycvv = $1;
      }
    }
  }

} else {
  die "unknown payby $payby";
}

my $error = '';
if ( $cgi->param('batch') ) {

  $error = $cust_main->batch_card(
                                   'payby'    => $payby,
                                   'amount'   => $amount,
                                   'payinfo'  => $payinfo,
                                   'paydate'  => "$year-$month-01",
                                   'payname'  => $payname,
                                   map { $_ => $cgi->param($_) } 
                                     @{$payby2fields{$payby}}
                                 );
  eidiot($error) if $error;

} else {

  $error = $cust_main->realtime_bop( $FS::payby::payby2bop{$payby}, $amount,
    'quiet'     => 1,
    'manual'    => 1,
    'payinfo'   => $payinfo,
    'paydate'   => "$year-$month-01",
    'payname'   => $payname,
    'payunique' => $payunique,
    'paycvv'    => $paycvv,
    map { $_ => $cgi->param($_) } @{$payby2fields{$payby}}
  );
  eidiot($error) if $error;

  $cust_main->apply_payments;

}

if ( $cgi->param('save') ) {
  my $new = new FS::cust_main { $cust_main->hash };
  if ( $payby eq 'CARD' ) { 
    $new->set( 'payby' => ( $cgi->param('auto') ? 'CARD' : 'DCRD' ) );
  } elsif ( $payby eq 'CHEK' ) {
    $new->set( 'payby' => ( $cgi->param('auto') ? 'CHEK' : 'DCHK' ) );
  } else {
    die "unknown payby $payby";
  }
  $new->set( 'payinfo' => $payinfo );
  $new->set( 'paydate' => "$year-$month-01" );
  $new->set( 'payname' => $payname );

  #false laziness w/FS:;cust_main::realtime_bop - check both to make sure
  # working correctly
  my $conf = new FS::Conf;
  if ( $payby eq 'CARD' &&
       grep { $_ eq cardtype($payinfo) } $conf->config('cvv-save') ) {
    $new->set( 'paycvv' => $paycvv );
  } else {
    $new->set( 'paycvv' => '');
  }

  $new->set( $_ => $cgi->param($_) ) foreach @{$payby2fields{$payby}};

  my $error = $new->replace($cust_main);
  eidiot "payment processed successfully, but error saving info: $error"
    if $error;
  $cust_main = $new;
}

#success!

</%init>
