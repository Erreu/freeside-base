package FS::cdr;

use strict;
use vars qw( @ISA @EXPORT_OK $DEBUG $me );
use Exporter;
use Tie::IxHash;
use Date::Parse;
use Date::Format;
use Time::Local;
use FS::UID qw( dbh );
use FS::Conf;
use FS::Record qw( qsearch qsearchs );
use FS::cdr_type;
use FS::cdr_calltype;
use FS::cdr_carrier;
use FS::cdr_batch;

@ISA = qw(FS::Record);
@EXPORT_OK = qw( _cdr_date_parser_maker _cdr_min_parser_maker );

$DEBUG = 0;
$me = '[FS::cdr]';

=head1 NAME

FS::cdr - Object methods for cdr records

=head1 SYNOPSIS

  use FS::cdr;

  $record = new FS::cdr \%hash;
  $record = new FS::cdr { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::cdr object represents an Call Data Record, typically from a telephony
system or provider of some sort.  FS::cdr inherits from FS::Record.  The
following fields are currently supported:

=over 4

=item acctid - primary key

=item calldate - Call timestamp (SQL timestamp)

=item clid - Caller*ID with text

=item src - Caller*ID number / Source number

=item dst - Destination extension

=item dcontext - Destination context

=item channel - Channel used

=item dstchannel - Destination channel if appropriate

=item lastapp - Last application if appropriate

=item lastdata - Last application data

=item startdate - Start of call (UNIX-style integer timestamp)

=item answerdate - Answer time of call (UNIX-style integer timestamp)

=item enddate - End time of call (UNIX-style integer timestamp)

=item duration - Total time in system, in seconds

=item billsec - Total time call is up, in seconds

=item disposition - What happened to the call: ANSWERED, NO ANSWER, BUSY 

=item amaflags - What flags to use: BILL, IGNORE etc, specified on a per channel basis like accountcode. 

=cut

  #ignore the "omit" and "documentation" AMAs??
  #AMA = Automated Message Accounting. 
  #default: Sets the system default. 
  #omit: Do not record calls. 
  #billing: Mark the entry for billing 
  #documentation: Mark the entry for documentation.

=item accountcode - CDR account number to use: account

=item uniqueid - Unique channel identifier (Unitel/RSLCOM Event ID)

=item userfield - CDR user-defined field

=item cdr_type - CDR type - see L<FS::cdr_type> (Usage = 1, S&E = 7, OC&C = 8)

=item charged_party - Service number to be billed

=item upstream_currency - Wholesale currency from upstream

=item upstream_price - Wholesale price from upstream

=item upstream_rateplanid - Upstream rate plan ID

=item rated_price - Rated (or re-rated) price

=item distance - km (need units field?)

=item islocal - Local - 1, Non Local = 0

=item calltypenum - Type of call - see L<FS::cdr_calltype>

=item description - Description (cdr_type 7&8 only) (used for cust_bill_pkg.itemdesc)

=item quantity - Number of items (cdr_type 7&8 only)

=item carrierid - Upstream Carrier ID (see L<FS::cdr_carrier>) 

=cut

#Telstra =1, Optus = 2, RSL COM = 3

=item upstream_rateid - Upstream Rate ID

=item svcnum - Link to customer service (see L<FS::cust_svc>)

=item freesidestatus - NULL, done (or something)

=item freesiderewritestatus - NULL, done (or something)

=item cdrbatch

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new CDR.  To add the CDR to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'cdr'; }

sub table_info {
  {
    'fields' => {
#XXX fill in some (more) nice names
        #'acctid'                => '',
        'calldate'              => 'Call date',
        'clid'                  => 'Caller ID',
        'src'                   => 'Source',
        'dst'                   => 'Destination',
        'dcontext'              => 'Dest. context',
        'channel'               => 'Channel',
        'dstchannel'            => 'Destination channel',
        #'lastapp'               => '',
        #'lastdata'              => '',
        'startdate'             => 'Start date',
        'answerdate'            => 'Answer date',
        'enddate'               => 'End date',
        'duration'              => 'Duration',
        'billsec'               => 'Billable seconds',
        'disposition'           => 'Disposition',
        'amaflags'              => 'AMA flags',
        'accountcode'           => 'Account code',
        #'uniqueid'              => '',
        'userfield'             => 'User field',
        #'cdrtypenum'            => '',
        'charged_party'         => 'Charged party',
        #'upstream_currency'     => '',
        'upstream_price'        => 'Upstream price',
        #'upstream_rateplanid'   => '',
        #'ratedetailnum'         => '',
        'rated_price'           => 'Rated price',
        #'distance'              => '',
        #'islocal'               => '',
        #'calltypenum'           => '',
        #'description'           => '',
        #'quantity'              => '',
        'carrierid'             => 'Carrier ID',
        #'upstream_rateid'       => '',
        'svcnum'                => 'Freeside service',
        'freesidestatus'        => 'Freeside status',
        'freesiderewritestatus' => 'Freeside rewrite status',
        'cdrbatch'              => 'Legacy batch',
        'cdrbatchnum'           => 'Batch',
    },

  };

}

=item insert

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

# the insert method can be inherited from FS::Record

=item delete

Delete this record from the database.

=cut

# the delete method can be inherited from FS::Record

=item replace OLD_RECORD

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

# the replace method can be inherited from FS::Record

=item check

Checks all fields to make sure this is a valid CDR.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

Note: Unlike most types of records, we don't want to "reject" a CDR and we want
to process them as quickly as possible, so we allow the database to check most
of the data.

=cut

sub check {
  my $self = shift;

# we don't want to "reject" a CDR like other sorts of input...
#  my $error = 
#    $self->ut_numbern('acctid')
##    || $self->ut_('calldate')
#    || $self->ut_text('clid')
#    || $self->ut_text('src')
#    || $self->ut_text('dst')
#    || $self->ut_text('dcontext')
#    || $self->ut_text('channel')
#    || $self->ut_text('dstchannel')
#    || $self->ut_text('lastapp')
#    || $self->ut_text('lastdata')
#    || $self->ut_numbern('startdate')
#    || $self->ut_numbern('answerdate')
#    || $self->ut_numbern('enddate')
#    || $self->ut_number('duration')
#    || $self->ut_number('billsec')
#    || $self->ut_text('disposition')
#    || $self->ut_number('amaflags')
#    || $self->ut_text('accountcode')
#    || $self->ut_text('uniqueid')
#    || $self->ut_text('userfield')
#    || $self->ut_numbern('cdrtypenum')
#    || $self->ut_textn('charged_party')
##    || $self->ut_n('upstream_currency')
##    || $self->ut_n('upstream_price')
#    || $self->ut_numbern('upstream_rateplanid')
##    || $self->ut_n('distance')
#    || $self->ut_numbern('islocal')
#    || $self->ut_numbern('calltypenum')
#    || $self->ut_textn('description')
#    || $self->ut_numbern('quantity')
#    || $self->ut_numbern('carrierid')
#    || $self->ut_numbern('upstream_rateid')
#    || $self->ut_numbern('svcnum')
#    || $self->ut_textn('freesidestatus')
#    || $self->ut_textn('freesiderewritestatus')
#  ;
#  return $error if $error;

  $self->calldate( $self->startdate_sql )
    if !$self->calldate && $self->startdate;

  #was just for $format eq 'taqua' but can't see the harm... add something to
  #disable if it becomes a problem
  if ( $self->duration eq '' && $self->enddate && $self->startdate ) {
    $self->duration( $self->enddate - $self->startdate  );
  }
  if ( $self->billsec eq '' && $self->enddate && $self->answerdate ) {
    $self->billsec(  $self->enddate - $self->answerdate );
  } 

  $self->set_charged_party;

  #check the foreign keys even?
  #do we want to outright *reject* the CDR?
  my $error =
       $self->ut_numbern('acctid')

  #add a config option to turn these back on if someone needs 'em
  #
  #  #Usage = 1, S&E = 7, OC&C = 8
  #  || $self->ut_foreign_keyn('cdrtypenum',  'cdr_type',     'cdrtypenum' )
  #
  #  #the big list in appendix 2
  #  || $self->ut_foreign_keyn('calltypenum', 'cdr_calltype', 'calltypenum' )
  #
  #  # Telstra =1, Optus = 2, RSL COM = 3
  #  || $self->ut_foreign_keyn('carrierid', 'cdr_carrier', 'carrierid' )
  ;
  return $error if $error;

  $self->SUPER::check;
}

=item is_tollfree

  Returns true when the cdr represents a toll free number and false otherwise.

=cut

sub is_tollfree {
  my $self = shift;
  ( $self->dst =~ /^(\+?1)?8(8|([02-7])\3)/ ) ? 1 : 0;
}

=item set_charged_party

If the charged_party field is already set, does nothing.  Otherwise:

If the cdr-charged_party-accountcode config option is enabled, sets the
charged_party to the accountcode.

Otherwise sets the charged_party normally: to the src field in most cases,
or to the dst field if it is a toll free number.

=cut

sub set_charged_party {
  my $self = shift;

  my $conf = new FS::Conf;

  unless ( $self->charged_party ) {

    if ( $conf->exists('cdr-charged_party-accountcode') && $self->accountcode ){

      my $charged_party = $self->accountcode;
      $charged_party =~ s/^0+//
        if $conf->exists('cdr-charged_party-accountcode-trim_leading_0s');
      $self->charged_party( $charged_party );

    } else {

      if ( $self->is_tollfree ) {
        $self->charged_party($self->dst);
      } else {
        $self->charged_party($self->src);
      }

    }

  }

#  my $prefix = $conf->config('cdr-charged_party-truncate_prefix');
#  my $prefix_len = length($prefix);
#  my $trunc_len = $conf->config('cdr-charged_party-truncate_length');
#
#  $self->charged_party( substr($self->charged_party, 0, $trunc_len) )
#    if $prefix_len && $trunc_len
#    && substr($self->charged_party, 0, $prefix_len) eq $prefix;

}

=item set_status_and_rated_price STATUS [ RATED_PRICE [ SVCNUM ] ]

Sets the status to the provided string.  If there is an error, returns the
error, otherwise returns false.

=cut

sub set_status_and_rated_price {
  my($self, $status, $rated_price, $svcnum) = @_;
  $self->freesidestatus($status);
  $self->rated_price($rated_price);
  $self->svcnum($svcnum) if $svcnum;
  $self->replace();
}

=item calldate_unix 

Parses the calldate in SQL string format and returns a UNIX timestamp.

=cut

sub calldate_unix {
  str2time(shift->calldate);
}

=item startdate_sql

Parses the startdate in UNIX timestamp format and returns a string in SQL
format.

=cut

sub startdate_sql {
  my($sec,$min,$hour,$mday,$mon,$year) = localtime(shift->startdate);
  $mon++;
  $year += 1900;
  "$year-$mon-$mday $hour:$min:$sec";
}

=item cdr_carrier

Returns the FS::cdr_carrier object associated with this CDR, or false if no
carrierid is defined.

=cut

my %carrier_cache = ();

sub cdr_carrier {
  my $self = shift;
  return '' unless $self->carrierid;
  $carrier_cache{$self->carrierid} ||=
    qsearchs('cdr_carrier', { 'carrierid' => $self->carrierid } );
}

=item carriername 

Returns the carrier name (see L<FS::cdr_carrier>), or the empty string if
no FS::cdr_carrier object is assocated with this CDR.

=cut

sub carriername {
  my $self = shift;
  my $cdr_carrier = $self->cdr_carrier;
  $cdr_carrier ? $cdr_carrier->carriername : '';
}

=item cdr_calltype

Returns the FS::cdr_calltype object associated with this CDR, or false if no
calltypenum is defined.

=cut

my %calltype_cache = ();

sub cdr_calltype {
  my $self = shift;
  return '' unless $self->calltypenum;
  $calltype_cache{$self->calltypenum} ||=
    qsearchs('cdr_calltype', { 'calltypenum' => $self->calltypenum } );
}

=item calltypename 

Returns the call type name (see L<FS::cdr_calltype>), or the empty string if
no FS::cdr_calltype object is assocated with this CDR.

=cut

sub calltypename {
  my $self = shift;
  my $cdr_calltype = $self->cdr_calltype;
  $cdr_calltype ? $cdr_calltype->calltypename : '';
}

=item downstream_csv [ OPTION => VALUE, ... ]

=cut

my %export_names = (
  'simple'  => {
    'name'           => 'Simple',
    'invoice_header' => "Date,Time,Name,Destination,Duration,Price",
  },
  'simple2' => {
    'name'           => 'Simple with source',
    'invoice_header' => "Date,Time,Called From,Destination,Duration,Price",
                       #"Date,Time,Name,Called From,Destination,Duration,Price",
  },
  'default' => {
    'name'           => 'Default',
    'invoice_header' => 'Date,Time,Number,Destination,Duration,Price',
  },
  'source_default' => {
    'name'           => 'Default with source',
    'invoice_header' => 'Caller,Date,Time,Number,Destination,Duration,Price',
  },
  'accountcode_default' => {
    'name'           => 'Default plus accountcode',
    'invoice_header' => 'Date,Time,Account,Number,Destination,Duration,Price',
  },
);

my $duration_sub = sub {
  my($cdr, %opt) = @_;
  if ( $opt{minutes} ) {
    $opt{minutes}. ( $opt{granularity} ? 'm' : ' call' );
  } else {
    #config if anyone really wants decimal minutes back
    #sprintf('%.2fm', $cdr->billsec / 60 );
    int($cdr->billsec / 60).'m '. ($cdr->billsec % 60).'s';
  }
};

my %export_formats = (
  'simple' => [
    sub { time2str('%D', shift->calldate_unix ) },   #DATE
    sub { time2str('%r', shift->calldate_unix ) },   #TIME
    'userfield',                                     #USER
    'dst',                                           #NUMBER_DIALED
    $duration_sub,                                   #DURATION
    #sub { sprintf('%.3f', shift->upstream_price ) }, #PRICE
    sub { my($cdr, %opt) = @_; $opt{money_char}. $opt{charge}; }, #PRICE
  ],
  'simple2' => [
    sub { time2str('%D', shift->calldate_unix ) },   #DATE
    sub { time2str('%r', shift->calldate_unix ) },   #TIME
    #'userfield',                                     #USER
    'src',                                           #called from
    'dst',                                           #NUMBER_DIALED
    $duration_sub,                                   #DURATION
    #sub { sprintf('%.3f', shift->upstream_price ) }, #PRICE
    sub { my($cdr, %opt) = @_; $opt{money_char}. $opt{charge}; }, #PRICE
  ],
  'default' => [

    #DATE
    sub { time2str('%D', shift->calldate_unix ) },
          # #time2str("%Y %b %d - %r", $cdr->calldate_unix ),

    #TIME
    sub { time2str('%r', shift->calldate_unix ) },
          # time2str("%c", $cdr->calldate_unix),  #XXX this should probably be a config option dropdown so they can select US vs- rest of world dates or whatnot

    #DEST ("Number")
    sub { my($cdr, %opt) = @_; $opt{pretty_dst} || $cdr->dst; },

    #REGIONNAME ("Destination")
    sub { my($cdr, %opt) = @_; $opt{dst_regionname}; },

    #DURATION
    $duration_sub,

    #PRICE
    sub { my($cdr, %opt) = @_; $opt{money_char}. $opt{charge}; },

  ],
);
$export_formats{'source_default'} = [ 'src', @{ $export_formats{'default'} }, ];
$export_formats{'accountcode_default'} =
  [ @{ $export_formats{'default'} }[0,1],
    'accountcode',
    @{ $export_formats{'default'} }[2..5],
  ];

sub downstream_csv {
  my( $self, %opt ) = @_;

  my $format = $opt{'format'};
  return "Unknown format $format" unless exists $export_formats{$format};

  #my $conf = new FS::Conf;
  #$opt{'money_char'} ||= $conf->config('money_char') || '$';
  $opt{'money_char'} ||= FS::Conf->new->config('money_char') || '$';

  eval "use Text::CSV_XS;";
  die $@ if $@;
  my $csv = new Text::CSV_XS;

  my @columns =
    map {
          ref($_) ? &{$_}($self, %opt) : $self->$_();
        }
    @{ $export_formats{$format} };

  my $status = $csv->combine(@columns);
  die "FS::CDR: error combining ". $csv->error_input(). "into downstream CSV"
    unless $status;

  $csv->string;

}

=back

=head1 CLASS METHODS

=over 4

=item invoice_formats

Returns an ordered list of key value pairs containing invoice format names
as keys (for use with part_pkg::voip_cdr) and "pretty" format names as values.

=cut

sub invoice_formats {
  map { ($_ => $export_names{$_}->{'name'}) }
    grep { $export_names{$_}->{'invoice_header'} }
    keys %export_names;
}

=item invoice_header FORMAT

Returns a scalar containing the CSV column header for invoice format FORMAT.

=cut

sub invoice_header {
  my $format = shift;
  $export_names{$format}->{'invoice_header'};
}

=item import_formats

Returns an ordered list of key value pairs containing import format names
as keys (for use with batch_import) and "pretty" format names as values.

=cut

#false laziness w/part_pkg & part_export

my %cdr_info;
foreach my $INC ( @INC ) {
  warn "globbing $INC/FS/cdr/*.pm\n" if $DEBUG;
  foreach my $file ( glob("$INC/FS/cdr/*.pm") ) {
    warn "attempting to load CDR format info from $file\n" if $DEBUG;
    $file =~ /\/(\w+)\.pm$/ or do {
      warn "unrecognized file in $INC/FS/cdr/: $file\n";
      next;
    };
    my $mod = $1;
    my $info = eval "use FS::cdr::$mod; ".
                    "\\%FS::cdr::$mod\::info;";
    if ( $@ ) {
      die "error using FS::cdr::$mod (skipping): $@\n" if $@;
      next;
    }
    unless ( keys %$info ) {
      warn "no %info hash found in FS::cdr::$mod, skipping\n";
      next;
    }
    warn "got CDR format info from FS::cdr::$mod: $info\n" if $DEBUG;
    if ( exists($info->{'disabled'}) && $info->{'disabled'} ) {
      warn "skipping disabled CDR format FS::cdr::$mod" if $DEBUG;
      next;
    }
    $cdr_info{$mod} = $info;
  }
}

tie my %import_formats, 'Tie::IxHash',
  map  { $_ => $cdr_info{$_}->{'name'} }
  sort { $cdr_info{$a}->{'weight'} <=> $cdr_info{$b}->{'weight'} }
  grep { exists($cdr_info{$_}->{'import_fields'}) }
  keys %cdr_info;

sub import_formats {
  %import_formats;
}

sub _cdr_min_parser_maker {
  my $field = shift;
  my @fields = ref($field) ? @$field : ($field);
  @fields = qw( billsec duration ) unless scalar(@fields) && $fields[0];
  return sub {
    my( $cdr, $min ) = @_;
    my $sec = eval { _cdr_min_parse($min) };
    die "error parsing seconds for @fields from $min minutes: $@\n" if $@;
    $cdr->$_($sec) foreach @fields;
  };
}

sub _cdr_min_parse {
  my $min = shift;
  sprintf('%.0f', $min * 60 );
}

sub _cdr_date_parser_maker {
  my $field = shift;
  my %options = @_;
  my @fields = ref($field) ? @$field : ($field);
  return sub {
    my( $cdr, $datestring ) = @_;
    my $unixdate = eval { _cdr_date_parse($datestring, %options) };
    die "error parsing date for @fields from $datestring: $@\n" if $@;
    $cdr->$_($unixdate) foreach @fields;
  };
}

sub _cdr_date_parse {
  my $date = shift;
  my %options = @_;

  return '' unless length($date); #that's okay, it becomes NULL
  return '' if $date eq 'NA'; #sansay

  if ( $date =~ /^([a-z]{3})\s+([a-z]{3})\s+(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})\s+(\d{4})$/i && $7 > 1970 ) {
    my $time = str2time($date);
    return $time if $time > 100000; #just in case
  }

  my($year, $mon, $day, $hour, $min, $sec);

  #$date =~ /^\s*(\d{4})[\-\/]\(\d{1,2})[\-\/](\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})\s*$/
  #taqua  #2007-10-31 08:57:24.113000000

  if ( $date =~ /^\s*(\d{4})\D(\d{1,2})\D(\d{1,2})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})(\D|$)/ ) {
    ($year, $mon, $day, $hour, $min, $sec) = ( $1, $2, $3, $4, $5, $6 );
  } elsif ( $date  =~ /^\s*(\d{1,2})\D(\d{1,2})\D(\d{4})\s+(\d{1,2})\D(\d{1,2})\D(\d{1,2})(\D|$)/ ) {
    ($mon, $day, $year, $hour, $min, $sec) = ( $1, $2, $3, $4, $5, $6 );
  } elsif ( $date  =~ /^\s*(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d+\.\d+)(\D|$)/ ) {
    # broadsoft: 20081223201938.314
    ($year, $mon, $day, $hour, $min, $sec) = ( $1, $2, $3, $4, $5, $6);
  } else {
     die "unparsable date: $date"; #maybe we shouldn't die...
  }

  return '' if ( $year == 1900 || $year == 1970 ) && $mon == 1 && $day == 1
            && $hour == 0 && $min == 0 && $sec == 0;

  if ($options{gmt}) {
    timegm($sec, $min, $hour, $day, $mon-1, $year);
  } else {
    timelocal($sec, $min, $hour, $day, $mon-1, $year);
  }
}

=item batch_import HASHREF

Imports CDR records.  Available options are:

=over 4

=item file

Filename

=item format

=item params

Hash reference of preset fields, typically cdrbatch

=item empty_ok

Set true to prevent throwing an error on empty imports

=back

=cut

my %import_options = (
  'table'         => 'cdr',

  'batch_keycol'  => 'cdrbatchnum',
  'batch_table'   => 'cdr_batch',
  'batch_namecol' => 'cdrbatch',

  'formats' => { map { $_ => $cdr_info{$_}->{'import_fields'}; }
                     keys %cdr_info
               },

                          #drop the || 'csv' to allow auto xls for csv types?
  'format_types' => { map { $_ => ( lc($cdr_info{$_}->{'type'}) || 'csv' ); }
                          keys %cdr_info
                    },

  'format_headers' => { map { $_ => ( $cdr_info{$_}->{'header'} || 0 ); }
                            keys %cdr_info
                      },

  'format_sep_chars' => { map { $_ => $cdr_info{$_}->{'sep_char'}; }
                              keys %cdr_info
                        },

  'format_fixedlength_formats' =>
    { map { $_ => $cdr_info{$_}->{'fixedlength_format'}; }
          keys %cdr_info
    },
);

sub _import_options {
  \%import_options;
}

sub batch_import {
  my $opt = shift;

  my $iopt = _import_options;
  $opt->{$_} = $iopt->{$_} foreach keys %$iopt;

  FS::Record::batch_import( $opt );

}

=item process_batch_import

=cut

sub process_batch_import {
  my $job = shift;

  my $opt = _import_options;
#  $opt->{'params'} = [ 'format', 'cdrbatch' ];

  FS::Record::process_batch_import( $job, $opt, @_ );

}
#  if ( $format eq 'simple' ) { #should be a callback or opt in FS::cdr::simple
#    @columns = map { s/^ +//; $_; } @columns;
#  }

# _ upgrade_data
#
# Used by FS::Upgrade to migrate to a new database.

sub _upgrade_data {
  my ($class, %opts) = @_;

  warn "$me upgrading $class\n" if $DEBUG;

  my $sth = dbh->prepare(
    'SELECT DISTINCT(cdrbatch) FROM cdr WHERE cdrbatch IS NOT NULL'
  ) or die dbh->errstr;

  $sth->execute or die $sth->errstr;

  my %cdrbatchnum = ();
  while (my $row = $sth->fetchrow_arrayref) {
    my $cdr_batch = new FS::cdr_batch { 'cdrbatch' => $row->[0] };
    my $error = $cdr_batch->insert;
    die $error if $error;
    $cdrbatchnum{$row->[0]} = $cdr_batch->cdrbatchnum;
  }

  $sth = dbh->prepare('UPDATE cdr SET cdrbatch = NULL, cdrbatchnum = ? WHERE cdrbatch IS NOT NULL AND cdrbatch = ?') or die dbh->errstr;

  foreach my $cdrbatch (keys %cdrbatchnum) {
    $sth->execute($cdrbatchnum{$cdrbatch}, $cdrbatch) or die $sth->errstr;
  }

}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut

1;

