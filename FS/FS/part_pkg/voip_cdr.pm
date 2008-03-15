package FS::part_pkg::voip_cdr;

use strict;
use vars qw(@ISA $DEBUG %info);
use Date::Format;
use Tie::IxHash;
use FS::Conf;
use FS::Record qw(qsearchs qsearch);
use FS::part_pkg::flat;
#use FS::rate;
#use FS::rate_prefix;

@ISA = qw(FS::part_pkg::flat);

$DEBUG = 1;

tie my %rating_method, 'Tie::IxHash',
  'prefix' => 'Rate calls by using destination prefix to look up a region and rate according to the internal prefix and rate tables',
  'upstream' => 'Rate calls based on upstream data: If the call type is "1", map the upstream rate ID directly to an internal rate (rate_detail), otherwise, pass the upstream price through directly.',
;

#tie my %cdr_location, 'Tie::IxHash',
#  'internal' => 'Internal: CDR records imported into the internal CDR table',
#  'external' => 'External: CDR records queried directly from an external '.
#                'Asterisk (or other?) CDR table',
#;

%info = (
  'name' => 'VoIP rating by plan of CDR records in an internal (or external) SQL table',
  'fields' => {
    'setup_fee'     => { 'name' => 'Setup fee for this package',
                         'default' => 0,
                       },
    'recur_flat'     => { 'name' => 'Base recurring fee for this package',
                          'default' => 0,
                        },
    'unused_credit' => { 'name' => 'Credit the customer for the unused portion'.
                                   ' of service at cancellation',
                         'type' => 'checkbox',
                       },
    'ratenum'   => { 'name' => 'Rate plan',
                     'type' => 'select',
                     'select_table' => 'rate',
                     'select_key'   => 'ratenum',
                     'select_label' => 'ratename',
                   },
    'rating_method' => { 'name' => 'Region rating method',
                         'type' => 'select',
                         'select_options' => \%rating_method,
                       },

    'default_prefix' => { 'name'    => 'Default prefix optionally prepended to customer DID numbers when searching for CDR records',
                          'default' => '+1',
                        },

    'disable_src' => { 'name' => 'Disable rating of CDR records based on the "src" field in addition to "charged_party"',
                       'type' => 'checkbox'
                     },

    'domestic_prefix' => { 'name'    => 'Destination prefix for domestic CDR records',
                           'default' => '1',
                         },

#    'domestic_prefix_required' => { 'name' => 'Require explicit destination prefix for domestic CDR records',
#                                    'type' => 'checkbox',
#                                  },

    'international_prefix' => { 'name'    => 'Destination prefix for international CDR records',
                                'default' => '011',
                              },

    #XXX also have option for an external db
#    'cdr_location' => { 'name' => 'CDR database location'
#                        'type' => 'select',
#                        'select_options' => \%cdr_location,
#                        'select_callback' => {
#                          'external' => {
#                            'enable' => [ 'datasrc', 'username', 'password' ],
#                          },
#                          'internal' => {
#                            'disable' => [ 'datasrc', 'username', 'password' ],
#                          }
#                        },
#                      },
#    'datasrc' => { 'name' => 'DBI data source for external CDR table',
#                   'disabled' => 'Y',
#                 },
#    'username' => { 'name' => 'External database username',
#                    'disabled' => 'Y',
#                  },
#    'password' => { 'name' => 'External database password',
#                    'disabled' => 'Y',
#                  },

  },
  'fieldorder' => [qw( setup_fee recur_flat unused_credit ratenum rating_method default_prefix )],
  'weight' => 40,
);

sub calc_setup {
  my($self, $cust_pkg ) = @_;
  $self->option('setup_fee');
}

#false laziness w/voip_sqlradacct... resolve it if that one ever gets used again
sub calc_recur {
  my($self, $cust_pkg, $sdate, $details, $param ) = @_;

  my $last_bill = $cust_pkg->last_bill;

  my $ratenum = $cust_pkg->part_pkg->option('ratenum');

  my $spool_cdr = $cust_pkg->cust_main->spool_cdr;

  my %included_min = ();

  my $charges = 0;

  my $downstream_cdr = '';

  foreach my $cust_svc (
    grep { $_->part_svc->svcdb eq 'svc_phone' } $cust_pkg->cust_svc
  ) {

    foreach my $cdr (
      $cust_svc->get_cdrs_for_update()  # $last_bill, $$sdate )
    ) {
      if ( $DEBUG > 1 ) {
        warn "rating CDR $cdr\n".
             join('', map { "  $_ => ". $cdr->{$_}. "\n" } keys %$cdr );
      }

      my $rate_detail;
      my( $rate_region, $regionnum );
      my $pretty_destnum;
      my $charge = 0;
      my @call_details = ();
      if ( $self->option('rating_method') eq 'prefix'
           || ! $self->option('rating_method')
         )
      {

        ###
        # look up rate details based on called station id
        # (or calling station id for toll free calls)
        ###

        my( $to_or_from, $number );
        if ( $cdr->dst =~ /^(\+?1)?8([02-8])\1/ ) { #tollfree call
          $to_or_from = 'from';
          $number = $cdr->src;
        } else { #regular call
          $to_or_from = 'to';
          $number = $cdr->dst;
        }
  
        #remove non-phone# stuff and whitespace
        $number =~ s/\s//g;
#        my $proto = '';
#        $dest =~ s/^(\w+):// and $proto = $1; #sip:
#        my $siphost = '';
#        $dest =~ s/\@(.*)$// and $siphost = $1; # @10.54.32.1, @sip.example.com

        my $intl = $self->option('international_prefix') || '011';
  
        #determine the country code
        my $countrycode;
        if (    $number =~ /^$intl(((\d)(\d))(\d))(\d+)$/
             || $number =~ /^\+(((\d)(\d))(\d))(\d+)$/
           )
        {
  
          my( $three, $two, $one, $u1, $u2, $rest ) = ( $1,$2,$3,$4,$5,$6 );
          #first look for 1 digit country code
          if ( qsearch('rate_prefix', { 'countrycode' => $one } ) ) {
            $countrycode = $one;
            $number = $u1.$u2.$rest;
          } elsif ( qsearch('rate_prefix', { 'countrycode' => $two } ) ) { #or 2
            $countrycode = $two;
            $number = $u2.$rest;
          } else { #3 digit country code
            $countrycode = $three;
            $number = $rest;
          }
  
        } else {
          $countrycode = $self->option('domestic_prefix') || '1';
          $number =~ s/^$countrycode//;# if length($number) > 10;
        }
  
        warn "rating call $to_or_from +$countrycode $number\n" if $DEBUG;
        $pretty_destnum = "+$countrycode $number";
  
        #find a rate prefix, first look at most specific (4 digits) then 3, etc.,
        # finally trying the country code only
        my $rate_prefix = '';
        for my $len ( reverse(1..6) ) {
          $rate_prefix = qsearchs('rate_prefix', {
            'countrycode' => $countrycode,
            #'npa'         => { op=> 'LIKE', value=> substr($number, 0, $len) }
            'npa'         => substr($number, 0, $len),
          } ) and last;
        }
        $rate_prefix ||= qsearchs('rate_prefix', {
          'countrycode' => $countrycode,
          'npa'         => '',
        });

        #
        die "Can't find rate for call $to_or_from +$countrycode $\numbern"
          unless $rate_prefix;
  
        $regionnum = $rate_prefix->regionnum;
        $rate_detail = qsearchs('rate_detail', {
          'ratenum'        => $ratenum,
          'dest_regionnum' => $regionnum,
        } );
  
        $rate_region = $rate_prefix->rate_region;

        warn "  found rate for regionnum $regionnum ".
             "and rate detail $rate_detail\n"
          if $DEBUG;

      } elsif ( $self->option('rating_method') eq 'upstream' ) {

        if ( $cdr->cdrtypenum == 1 ) { #rate based on upstream rateid

          $rate_detail = $cdr->cdr_upstream_rate->rate_detail;

          $regionnum = $rate_detail->dest_regionnum;
          $rate_region = $rate_detail->dest_region;

          $pretty_destnum = $cdr->dst;

          warn "  found rate for regionnum $regionnum and ".
               "rate detail $rate_detail\n"
            if $DEBUG;

        } else { #pass upstream price through

          $charge = sprintf('%.2f', $cdr->upstream_price);
  
          @call_details = (
            #time2str("%Y %b %d - %r", $cdr->calldate_unix ),
            time2str("%c", $cdr->calldate_unix),  #XXX this should probably be a config option dropdown so they can select US vs- rest of world dates or whatnot
            'N/A', #minutes...
            '$'.$charge,
            #$pretty_destnum,
            $cdr->description, #$rate_region->regionname,
          );

        }

      } else {
        die "don't know how to rate CDRs using method: ".
            $self->option('rating_method'). "\n";
      }

      ###
      # find the price and add detail to the invoice
      ###

      # if $rate_detail is not found, skip this CDR... i.e. 
      # don't add it to invoice, don't set its status to NULL,
      # don't call downstream_csv or something on it...
      # but DO emit a warning...
      if ( ! $rate_detail && ! scalar(@call_details) ) {
  
        warn "no rate_detail found for CDR.acctid:  ". $cdr->acctid.
             "; skipping\n"

      } else { # there *is* a rate_detail (or call_details), proceed...

        unless ( @call_details ) {
    
          $included_min{$regionnum} = $rate_detail->min_included
            unless exists $included_min{$regionnum};
      
          my $granularity = $rate_detail->sec_granularity;
          my $seconds = $cdr->billsec; # |ength($cdr->billsec) ? $cdr->billsec : $cdr->duration;
          $seconds += $granularity - ( $seconds % $granularity )
            if $granularity; # 0 is per call
          my $minutes = sprintf("%.1f", $seconds / 60);
          $minutes =~ s/\.0$// if $granularity == 60;

          # per call rather than per minute
          $minutes = 1 unless $granularity;
      
          $included_min{$regionnum} -= $minutes;
      
          if ( $included_min{$regionnum} < 0 ) {
            my $charge_min = 0 - $included_min{$regionnum};
            $included_min{$regionnum} = 0;
            $charge = sprintf('%.2f', $rate_detail->min_charge * $charge_min );
            $charges += $charge;
          }
      
          # this is why we need regionnum/rate_region....
          warn "  (rate region $rate_region)\n" if $DEBUG;
      
          @call_details = (
            #time2str("%Y %b %d - %r", $cdr->calldate_unix ),
            time2str("%c", $cdr->calldate_unix),  #XXX this should probably be a config option dropdown so they can select US vs- rest of world dates or whatnot
            $granularity ? $minutes.'m' : $minutes.' call',
            '$'.$charge,
            $pretty_destnum,
            $rate_region->regionname,
          );

        }
    
        warn "  adding details on charge to invoice: ".
             join(' - ', @call_details )
          if $DEBUG;
    
        push @$details, join(' - ', @call_details); #\@call_details,
  
        # if the customer flag is on, call "downstream_csv" or something
        # like it to export the call downstream!
        # XXX price plan option to pick format, or something...
        $downstream_cdr .= $cdr->downstream_csv( 'format' => 'convergent' )
          if $spool_cdr;
  
        my $error = $cdr->set_status_and_rated_price('done', $charge);
        die $error if $error;
  
      }
  
    } # $cdr

  } # $cust_svc

  if ( $spool_cdr && length($downstream_cdr) ) {

    use FS::UID qw(datasrc);
    my $dir = '/usr/local/etc/freeside/export.'. datasrc. '/cdr';
    mkdir $dir, 0700 unless -d $dir;
    $dir .= '/'. $cust_pkg->custnum.
    mkdir $dir, 0700 unless -d $dir;
    my $filename = time2str("$dir/CDR%Y%m%d-spool.CSV", time); #XXX invoice date instead?  would require changing the order things are generated in cust_main::bill insert cust_bill first - with transactions it could be done though

    push @{ $param->{'precommit_hooks'} },
         sub {
               #lock the downstream spool file and append the records 
               use Fcntl qw(:flock);
               use IO::File;
               my $spool = new IO::File ">>$filename"
                 or die "can't open $filename: $!\n";
               flock( $spool, LOCK_EX)
                 or die "can't lock $filename: $!\n";
               seek($spool, 0, 2)
                 or die "can't seek to end of $filename: $!\n";
               print $spool $downstream_cdr;
               flock( $spool, LOCK_UN );
               close $spool;
             };

  } #if ( $spool_cdr && length($downstream_cdr) )

  $self->option('recur_flat') + $charges;

}

sub is_free {
  0;
}

sub base_recur {
  my($self, $cust_pkg) = @_;
  $self->option('recur_flat');
}

1;

