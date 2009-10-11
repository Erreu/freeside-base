package FS::cdr::taqua;

use strict;
use vars qw(@ISA %info $da_rewrite);
use FS::cdr qw(_cdr_date_parser_maker);

@ISA = qw(FS::cdr);

%info = (
  'name'          => 'Taqua',
  'weight'        => 130,
  'header'        => 1,
  'import_fields' => [  #some of these are kind arbitrary...

    #0
    #RecordType
    sub {
      my($cdr, $field, $conf, $hashref) = @_;
      $hashref->{skiprow} = 1 unless ($field == 0 && $cdr->disposition == 100);
      $cdr->cdrtypenum($field);
    },

    sub { my($cdr, $field) = @_; },             #all10#RecordVersion
    sub { my($cdr, $field) = @_; },       #OrigShelfNumber
    sub { my($cdr, $field) = @_; },       #OrigCardNumber
    sub { my($cdr, $field) = @_; },       #OrigCircuit
    sub { my($cdr, $field) = @_; },       #OrigCircuitType
    'uniqueid',                           #SequenceNumber
    'accountcode',                        #SessionNumber
    'src',                                #CallingPartyNumber
    #'dst',                                #CalledPartyNumber
    #CalledPartyNumber
    sub {
      my( $cdr, $field, $conf ) = @_;
      if ( $cdr->calltypenum == 6 && $cdr->cdrtypenum == 0 ) {
        $cdr->dst("+$field");
      } else {
        $cdr->dst($field);
      }
    },

    #10
    _cdr_date_parser_maker('startdate', 'gmt' => 1),  #CallArrivalTime
    _cdr_date_parser_maker('enddate', 'gmt' => 1),    #CallCompletionTime

    #Disposition
    #sub { my($cdr, $d ) = @_; $cdr->disposition( $disposition{$d}): },
    'disposition',
                                          #  -1 => '',
                                          #   0 => '',
                                          # 100 => '',
                                          # 101 => '',
                                          # 102 => '',
                                          # 103 => '',
                                          # 104 => '',
                                          # 105 => '',
                                          # 201 => '',
                                          # 203 => '',

    _cdr_date_parser_maker('answerdate', 'gmt' => 1), #DispositionTime
    sub { my($cdr, $field) = @_; },       #TCAP
    sub { my($cdr, $field) = @_; },       #OutboundCarrierConnectTime
    sub { my($cdr, $field) = @_; },       #OutboundCarrierDisconnectTime

    #TermTrunkGroup
    #it appears channels are actually part of trunk groups, but this data
    #is interesting and we need a source and destination place to put it
    'dstchannel',                         #TermTrunkGroup


    sub { my($cdr, $field) = @_; },       #TermShelfNumber
    sub { my($cdr, $field) = @_; },       #TermCardNumber

    #20
    sub { my($cdr, $field) = @_; },       #TermCircuit
    sub { my($cdr, $field) = @_; },       #TermCircuitType
    'carrierid',                          #OutboundCarrierId

    #BillingNumber
    #'charged_party',                      
    sub {
      my( $cdr, $field, $conf ) = @_;

      #could be more efficient for the no config case, if anyone ever needs that
      $da_rewrite ||= $conf->config('cdr-taqua-da_rewrite');

      if ( $da_rewrite && $field =~ /\d/ ) {
        my $rewrite = $da_rewrite;
        $rewrite =~ s/\s//g;
        my @rewrite = split(',', $conf->config('cdr-taqua-da_rewrite') );
        if ( grep { $field eq $_ } @rewrite ) {
          $cdr->charged_party( $cdr->src() );
          $cdr->calltypenum(12);
          return;
        }
      }
      if ( $cdr->is_tollfree ) {        # thankfully this is already available
        $cdr->charged_party($cdr->dst); # and this
      } else {
        $cdr->charged_party($field);
      }
    },

    sub { my($cdr, $field) = @_; },       #SubscriberNumber
    'lastapp',                            #ServiceName
    sub { my($cdr, $field) = @_; },       #some weirdness #ChargeTime
    'lastdata',                           #ServiceInformation
    sub { my($cdr, $field) = @_; },       #FacilityInfo
    sub { my($cdr, $field) = @_; },             #all 1900-01-01 0#CallTraceTime

    #30
    sub { my($cdr, $field) = @_; },             #all-1#UniqueIndicator
    sub { my($cdr, $field) = @_; },             #all-1#PresentationIndicator
    sub { my($cdr, $field) = @_; },             #empty#Pin
    'calltypenum',                        #CallType

    #nothing below is used by QIS...

    sub { my($cdr, $field) = @_; },           #Balt/empty #OrigRateCenter
    sub { my($cdr, $field) = @_; },           #Balt/empty #TermRateCenter

    #OrigTrunkGroup
    #it appears channels are actually part of trunk groups, but this data
    #is interesting and we need a source and destination place to put it
    'channel',                            #OrigTrunkGroup

    'userfield',                                #empty#UserDefined
    sub { my($cdr, $field) = @_; },             #empty#PseudoDestinationNumber
    sub { my($cdr, $field) = @_; },             #all-1#PseudoCarrierCode

    #40
    sub { my($cdr, $field) = @_; },             #empty#PseudoANI
    sub { my($cdr, $field) = @_; },             #all-1#PseudoFacilityInfo
    sub { my($cdr, $field) = @_; },       #OrigDialedDigits
    sub { my($cdr, $field) = @_; },             #all-1#OrigOutboundCarrier
    sub { my($cdr, $field) = @_; },       #IncomingCarrierID
    'dcontext',                           #JurisdictionInfo
    sub { my($cdr, $field) = @_; },       #OrigDestDigits
    sub { my($cdr, $field) = @_; },       #huh?#InsertTime
    sub { my($cdr, $field) = @_; },       #key
    sub { my($cdr, $field) = @_; },             #empty#AMALineNumber

    #50
    sub { my($cdr, $field) = @_; },             #empty#AMAslpID
    sub { my($cdr, $field) = @_; },             #empty#AMADigitsDialedWC
    sub { my($cdr, $field) = @_; },       #OpxOffHook
    sub { my($cdr, $field) = @_; },       #OpxOnHook

        #acctid - primary key
  #AUTO #calldate - Call timestamp (SQL timestamp)
#clid - Caller*ID with text
        #XXX src - Caller*ID number / Source number
        #XXX dst - Destination extension
        #dcontext - Destination context
        #channel - Channel used
        #dstchannel - Destination channel if appropriate
        #lastapp - Last application if appropriate
        #lastdata - Last application data
        #startdate - Start of call (UNIX-style integer timestamp)
        #answerdate - Answer time of call (UNIX-style integer timestamp)
        #enddate - End time of call (UNIX-style integer timestamp)
  #HACK#duration - Total time in system, in seconds
  #HACK#XXX billsec - Total time call is up, in seconds
        #disposition - What happened to the call: ANSWERED, NO ANSWER, BUSY
#INT amaflags - What flags to use: BILL, IGNORE etc, specified on a per channel basis like accountcode.
        #accountcode - CDR account number to use: account

        #uniqueid - Unique channel identifier (Unitel/RSLCOM Event ID)
        #userfield - CDR user-defined field

        #X cdrtypenum - CDR type - see FS::cdr_type (Usage = 1, S&E = 7, OC&C = 8)
        #XXX charged_party - Service number to be billed
#upstream_currency - Wholesale currency from upstream
#X upstream_price - Wholesale price from upstream
#upstream_rateplanid - Upstream rate plan ID
#rated_price - Rated (or re-rated) price
#distance - km (need units field?)
#islocal - Local - 1, Non Local = 0
#calltypenum - Type of call - see FS::cdr_calltype
#X description - Description (cdr_type 7&8 only) (used for cust_bill_pkg.itemdesc)
#quantity - Number of items (cdr_type 7&8 only)
#carrierid - Upstream Carrier ID (see FS::cdr_carrier)
#upstream_rateid - Upstream Rate ID

        #svcnum - Link to customer service (see FS::cust_svc)
        #freesidestatus - NULL, done (or something)
  ],
);

1;
