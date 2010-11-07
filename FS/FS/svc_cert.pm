package FS::svc_cert;

use strict;
use base qw( FS::svc_Common );
#use FS::Record qw( qsearch qsearchs );
use FS::cust_svc;

=head1 NAME

FS::svc_cert - Object methods for svc_cert records

=head1 SYNOPSIS

  use FS::svc_cert;

  $record = new FS::svc_cert \%hash;
  $record = new FS::svc_cert { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::svc_cert object represents a certificate.  FS::svc_cert inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item svcnum

primary key

=item recnum

recnum

=item privatekey

privatekey

=item csr

csr

=item certificate

certificate

=item cacert

cacert

=item common_name

common_name

=item organization

organization

=item organization_unit

organization_unit

=item city

city

=item state

state

=item country

country

=item contact

contact


=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new certificate.  To add the certificate to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'svc_cert'; }

sub table_info {
  my %dis = ( disable_default=>1, disable_fixed=>1, disable_inventory=>1, disable_select=>1 );
  {
    'name' => 'Certificate',
    'name_plural' => 'Certificates',
    'longname_plural' => 'Example services', #optional
    'sorts' => 'svcnum', # optional sort field (or arrayref of sort fields, main first)
    'display_weight' => 25,
    'cancel_weight'  => 65,
    'fields' => {
      #'recnum'            => '',
      'privatekey'        => { label=>'Private key', %dis, },
      'csr'               => { label=>'Certificate signing request', %dis, },
      'certificate'       => { label=>'Certificate', %dis, },
      'cacert'            => { label=>'Certificate authority chain', %dis, },
      'common_name'       => { label=>'Common name', %dis, },
      'organization'      => { label=>'Organization', %dis, },
      'organization_unit' => { label=>'Organization Unit', %dis, },
      'city'              => { label=>'City', %dis, },
      'state'             => { label=>'State', %dis, },
      'country'           => { label=>'Country', %dis, },
      'cert_contact'      => { label=>'Contact', %dis, },
      
      #'another_field' => { 
      #                     'label'     => 'Description',
      #                     'def_label' => 'Description for service definitions',
      #                     'type'      => 'text',
      #                     'disable_default'   => 1, #disable switches
      #                     'disable_fixed'     => 1, #
      #                     'disable_inventory' => 1, #
      #                   },
      #'foreign_key'   => { 
      #                     'label'        => 'Description',
      #                     'def_label'    => 'Description for service defs',
      #                     'type'         => 'select',
      #                     'select_table' => 'foreign_table',
      #                     'select_key'   => 'key_field_in_table',
      #                     'select_label' => 'label_field_in_table',
      #                   },

    },
  };
}

=item label

Returns a meaningful identifier for this example

=cut

sub label {
  my $self = shift;
#  $self->label_field; #or something more complicated if necessary
  # check privatekey, check->privatekey, more?
  return 'Certificate';
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

Checks all fields to make sure this is a valid certificate.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

# the check method should currently be supplied - FS::Record contains some
# data checking routines

sub check {
  my $self = shift;

  my $error = 
    $self->ut_numbern('svcnum')
    || $self->ut_numbern('recnum')
    || $self->ut_anything('privatekey') #XXX
    || $self->ut_anything('csr')        #XXX
    || $self->ut_anything('certificate')#XXX
    || $self->ut_anything('cacert')     #XXX
    || $self->ut_textn('common_name')
    || $self->ut_textn('organization')
    || $self->ut_textn('organization_unit')
    || $self->ut_textn('city')
    || $self->ut_textn('state')
    || $self->ut_textn('country') #XXX char(2) or NULL
    || $self->ut_textn('contact')
  ;
  return $error if $error;

  $self->SUPER::check;
}

=item generate_privatekey [ KEYSIZE ]

=cut

use IPC::Run qw( run );
use File::Temp;

sub generate_privatekey {
  my $self = shift;
  my $keysize = (@_ && $_[0]) ? shift : 2048;
  run( [qw( openssl genrsa ), $keysize], '>pipe'=>\*OUT, '2>'=>'/dev/null' )
    or die "error running openssl: $!";
  #XXX error checking
  my $privatekey = join('', <OUT>);
  $self->privatekey($privatekey);
}

=item check_privatekey

=cut

sub check_privatekey {
  my $self = shift;
  my $in = $self->privatekey;
  run( [qw( openssl rsa -check -noout)], '<'=>\$in, '>pipe'=>\*OUT, '2>'=>'/dev/null' )
   ;# or die "error running openssl: $!";

  my $ok = <OUT>;
  return ($ok =~ /key ok/);
}

my %subj = (
  'CN' => 'common_name',
  'O'  => 'organization',
  'OU'  => 'organization_unit',
  'L' => 'city',
  'ST' => 'state',
  'C' => 'country',
);

sub subj {
  my $self = shift;

  '/'. join('/', map { my $v = $self->get($subj{$_});
                       $v =~ s/([=\/])/\\$1/;
                       "$_=$v";
                     }
                     keys %subj
           );
}

sub generate_csr {
  my $self = shift;
  my $in = $self->privatekey;
  my $dir = $FS::UID::conf_dir. "/cache.". $FS::UID::datasrc; #XXX actual cache dir
  my $fh = new File::Temp(
    TEMPLATE => 'certkey.'. '.XXXXXXXX',
    DIR      => $dir,
  ) or die "can't open temp file: $!\n";

  run( [qw( openssl req -new -key ), $fh->filename, '-subj', $self->subj ],
       '>pipe'=>\*OUT, '2>'=>'/dev/null'
     ) 
    or die "error running openssl: $!";
  #XXX error checking
  my $csr = join('', <OUT>);
  $self->csr($csr);
}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut

1;

