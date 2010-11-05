package FS::cdr::cia;

use strict;
use vars qw( @ISA %info );
use FS::cdr qw(_cdr_date_parser_maker);

@ISA = qw(FS::cdr);

%info = (
  'name'          => 'Client Instant Access',
  'weight'        => 510,
  'header'        => 1,
  'type'          => 'csv',
  'sep_char'      => "\t",
  'import_fields' => [
    skip(2),          # Reseller Account Number, Confirmation Number
    'description',    # Conference Name
    skip(3),          # Organization Name, Bill Code, Q&A Active 
    'userfield',      # Chairperson Name
    skip(2),          # Conference Start Time, Conference End Time
    _cdr_date_parser_maker('startdate'),  # Connect Time
    _cdr_date_parser_maker('enddate'),    # Disconnect Time
    sub { my($cdr, $data, $conf, $param) = @_;
          $cdr->duration($data);
          $cdr->billsec( $data);
    },                # Duration
    skip(2),          # Roundup Duration, User Name
    'dst',            # DNIS
    'src',            # ANI
    skip(2),          # Call Type, Toll Free, 
    skip(1),          # Chair Conference Entry Code
    'accountcode',    # Participant Conference Entry Code,
    ],

);

sub skip { map {''} (1..$_[0]) }

1;
