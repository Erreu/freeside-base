package FS::part_pkg::flat;

use strict;
use vars qw( @ISA %info
             %usage_fields %usage_recharge_fields
             @usage_fieldorder @usage_recharge_fieldorder
           );
use Tie::IxHash;
#use FS::Record qw(qsearch);
use FS::UI::bytecount;
use FS::part_pkg;

@ISA = qw(FS::part_pkg);

tie my %temporalities, 'Tie::IxHash',
  'upcoming'  => "Upcoming (future)",
  'preceding' => "Preceding (past)",
;

%usage_fields = (

    'seconds'       => { 'name' => 'Time limit for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                       },
    'upbytes'       => { 'name' => 'Upload limit for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
    'downbytes'     => { 'name' => 'Download limit for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
    'totalbytes'    => { 'name' => 'Transfer limit for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
);

%usage_recharge_fields = (

    'recharge_amount'       => { 'name' => 'Cost of recharge for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*(\.\d{2})?$/ },
                       },
    'recharge_seconds'      => { 'name' => 'Recharge time for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                       },
    'recharge_upbytes'      => { 'name' => 'Recharge upload for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
    'recharge_downbytes'    => { 'name' => 'Recharge download for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
    'recharge_totalbytes'   => { 'name' => 'Recharge transfer for this package',
                         'default' => '',
                         'check' => sub { shift =~ /^\d*$/ },
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
    'usage_rollover' => { 'name' => 'Allow usage from previous period to roll '.
                                    ' over into current period',
                          'type' => 'checkbox',
                        },
    'recharge_reset' => { 'name' => 'Reset usage to these values on manual '.
                                    'package recharge',
                          'type' => 'checkbox',
                        },
);

@usage_fieldorder = qw( seconds upbytes downbytes totalbytes );
@usage_recharge_fieldorder = qw(
  recharge_amount recharge_seconds recharge_upbytes
  recharge_downbytes recharge_totalbytes
  usage_rollover recharge_reset
);

%info = (
  'name' => 'Flat rate (anniversary billing)',
  'shortname' => 'Anniversary',
  'fields' => {
    'setup_fee'     => { 'name' => 'Setup fee for this package',
                         'default' => 0,
                       },
    'recur_fee'     => { 'name' => 'Recurring fee for this package',
                         'default' => 0,
                       },

    #false laziness w/voip_cdr.pm
    'recur_temporality' => { 'name' => 'Charge recurring fee for period',
                             'type' => 'select',
                             'select_options' => \%temporalities,
                           },
    'unused_credit' => { 'name' => 'Credit the customer for the unused portion'.
                                   ' of service at cancellation',
                         'type' => 'checkbox',
                       },

    #used in cust_pkg.pm so could add to any price plan
    'expire_months' => { 'name' => 'Auto-add an expiration date this number of months out',
                       },
    #used in cust_pkg.pm so could add to any price plan where it made sense
    'start_1st'     => { 'name' => 'Auto-add a start date to the 1st, ignoring the current month.',
                         'type' => 'checkbox',
                       },
    'unsuspend_adjust_bill' =>
                       { 'name' => 'Adjust next bill date forward when '.
                                   'unsuspending',
                         'type' => 'checkbox',
                       },

    %usage_fields,
    %usage_recharge_fields,

    'externalid' => { 'name'   => 'Optional External ID',
                      'default' => '',
                    },
  },
  'fieldorder' => [ qw( setup_fee recur_fee
                        recur_temporality unused_credit
                        expire_months start_1st unsuspend_adjust_bill
                      ),
                    @usage_fieldorder, @usage_recharge_fieldorder,
                    qw( externalid ),
                  ],
  'weight' => 10,
);

sub calc_setup {
  my($self, $cust_pkg, $sdate, $details ) = @_;

  my $i = 0;
  my $count = $self->option( 'additional_count', 'quiet' ) || 0;
  while ($i < $count) {
    push @$details, $self->option( 'additional_info' . $i++ );
  }

  my $quantity = $cust_pkg->quantity || 1;

  sprintf("%.2f", $quantity * $self->unit_setup($cust_pkg, $sdate, $details) );
}

sub unit_setup {
  my($self, $cust_pkg, $sdate, $details ) = @_;

  $self->option('setup_fee');
}

sub calc_recur {
  my $self = shift;
  my($cust_pkg) = @_;

  #my $last_bill = $cust_pkg->last_bill;
  my $last_bill = $cust_pkg->get('last_bill'); #->last_bill falls back to setup

  return 0
    if $self->option('recur_temporality', 1) eq 'preceding' && $last_bill == 0;

  $self->base_recur(@_);
}

sub base_recur {
  my($self, $cust_pkg) = @_;
  $self->option('recur_fee', 1) || 0;
}

sub base_recur_permonth {
  my($self, $cust_pkg) = @_;

  return 0 unless $self->freq =~ /^\d+$/ && $self->freq > 0;

  sprintf('%.2f', $self->base_recur($cust_pkg) / $self->freq );
}

sub calc_remain {
  my ($self, $cust_pkg, %options) = @_;

  my $time;
  if ($options{'time'}) {
    $time = $options{'time'};
  } else {
    $time = time;
  }

  my $next_bill = $cust_pkg->getfield('bill') || 0;

  #my $last_bill = $cust_pkg->last_bill || 0;
  my $last_bill = $cust_pkg->get('last_bill') || 0; #->last_bill falls back to setup

  return 0 if    ! $self->base_recur($cust_pkg)
              || ! $self->option('unused_credit', 1)
              || ! $last_bill
              || ! $next_bill
              || $next_bill < $time;

  my %sec = (
    'h' =>    3600, # 60 * 60
    'd' =>   86400, # 60 * 60 * 24
    'w' =>  604800, # 60 * 60 * 24 * 7
    'm' => 2629744, # 60 * 60 * 24 * 365.2422 / 12 
  );

  $self->freq =~ /^(\d+)([hdwm]?)$/
    or die 'unparsable frequency: '. $self->freq;
  my $freq_sec = $1 * $sec{$2||'m'};
  return 0 unless $freq_sec;

  sprintf("%.2f", $self->base_recur($cust_pkg) * ( $next_bill - $time ) / $freq_sec );

}

sub is_free_options {
  qw( setup_fee recur_fee );
}

sub is_prepaid {
  0; #no, we're postpaid
}

sub usage_valuehash {
  my $self = shift;
  map { $_, $self->option($_) }
    grep { $self->option($_, 'hush') } 
    qw(seconds upbytes downbytes totalbytes);
}

sub reset_usage {
  my($self, $cust_pkg, %opt) = @_;
  warn "   resetting usage counters" if defined($opt{debug}) && $opt{debug} > 1;
  my %values = $self->usage_valuehash;
  if ($self->option('usage_rollover', 1)) {
    $cust_pkg->recharge(\%values);
  }else{
    $cust_pkg->set_usage(\%values, %opt);
  }
}

1;
