package FS::svc_domain;

use strict;
use vars qw( @ISA $whois_hack $conf
  @defaultrecords $soadefaultttl $soaemail $soaexpire $soamachine
  $soarefresh $soaretry
);
use Carp;
use Date::Format;
#use Net::Whois::Raw;
use FS::Record qw(fields qsearch qsearchs dbh);
use FS::Conf;
use FS::svc_Common;
use FS::svc_Parent_Mixin;
use FS::cust_svc;
use FS::svc_acct;
use FS::cust_pkg;
use FS::cust_main;
use FS::domain_record;
use FS::queue;

@ISA = qw( FS::svc_Parent_Mixin FS::svc_Common );

#ask FS::UID to run this stuff for us later
$FS::UID::callback{'FS::domain'} = sub { 
  $conf = new FS::Conf;

  @defaultrecords = $conf->config('defaultrecords');
  $soadefaultttl = $conf->config('soadefaultttl');
  $soaemail      = $conf->config('soaemail');
  $soaexpire     = $conf->config('soaexpire');
  $soamachine    = $conf->config('soamachine');
  $soarefresh    = $conf->config('soarefresh');
  $soaretry      = $conf->config('soaretry');

};

=head1 NAME

FS::svc_domain - Object methods for svc_domain records

=head1 SYNOPSIS

  use FS::svc_domain;

  $record = new FS::svc_domain \%hash;
  $record = new FS::svc_domain { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

  $error = $record->suspend;

  $error = $record->unsuspend;

  $error = $record->cancel;

=head1 DESCRIPTION

An FS::svc_domain object represents a domain.  FS::svc_domain inherits from
FS::svc_Common.  The following fields are currently supported:

=over 4

=item svcnum - primary key (assigned automatically for new accounts)

=item domain

=item catchall - optional svcnum of an svc_acct record, designating an email catchall account.

=item suffix - 

=item parent_svcnum -

=item registrarnum - Registrar (see L<FS::registrar>)

=item registrarkey - Registrar key or password for this domain

=item setup_date - UNIX timestamp

=item renewal_interval - Number of days before expiration date to start renewal

=item expiration_date - UNIX timestamp

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new domain.  To add the domain to the database, see L<"insert">.

=cut

sub table_info {
  {
    'name' => 'Domain',
    'sorts' => 'domain',
    'display_weight' => 20,
    'cancel_weight'  => 60,
    'fields' => {
      'domain' => 'Domain',
    },
  };
}

sub table { 'svc_domain'; }

sub search_sql {
  my($class, $string) = @_;
  $class->search_sql_field('domain', $string);
}


=item label

Returns the domain.

=cut

sub label {
  my $self = shift;
  $self->domain;
}

=item insert [ , OPTION => VALUE ... ]

Adds this domain to the database.  If there is an error, returns the error,
otherwise returns false.

The additional fields I<pkgnum> and I<svcpart> (see L<FS::cust_svc>) should be 
defined.  An FS::cust_svc record will be created and inserted.

The additional field I<action> should be set to I<N> for new domains or I<M>
for transfers.

A registration or transfer email will be submitted unless
$FS::svc_domain::whois_hack is true.

The additional field I<email> can be used to manually set the admin contact
email address on this email.  Otherwise, the svc_acct records for this package 
(see L<FS::cust_pkg>) are searched.  If there is exactly one svc_acct record
in the same package, it is automatically used.  Otherwise an error is returned.

If any I<soamachine> configuration file exists, an SOA record is added to
the domain_record table (see <FS::domain_record>).

If any records are defined in the I<defaultrecords> configuration file,
appropriate records are added to the domain_record table (see
L<FS::domain_record>).

Currently available options are: I<depend_jobnum>

If I<depend_jobnum> is set (to a scalar jobnum or an array reference of
jobnums), all provisioning jobs will have a dependancy on the supplied
jobnum(s) (they will not run until the specific job(s) complete(s)).

=cut

sub insert {
  my $self = shift;
  my $error;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  $error = $self->check;
  return $error if $error;

  return "Domain in use (here)"
    if qsearchs( 'svc_domain', { 'domain' => $self->domain } );


  $error = $self->SUPER::insert(@_);
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  if ( $soamachine ) {
    my $soa = new FS::domain_record {
      'svcnum'  => $self->svcnum,
      'reczone' => '@',
      'recaf'   => 'IN',
      'rectype' => 'SOA',
      'recdata' => "$soamachine $soaemail ( ". time2str("%Y%m%d", time). "00 ".
                   "$soarefresh $soaretry $soaexpire $soadefaultttl )"
    };
    $error = $soa->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "couldn't insert SOA record for new domain: $error";
    }

    foreach my $record ( @defaultrecords ) {
      my($zone,$af,$type,$data) = split(/\s+/,$record,4);
      my $domain_record = new FS::domain_record {
        'svcnum'  => $self->svcnum,
        'reczone' => $zone,
        'recaf'   => $af,
        'rectype' => $type,
        'recdata' => $data,
      };
      my $error = $domain_record->insert;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "couldn't insert record for new domain: $error";
      }
    }

  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  ''; #no error
}

=item delete

Deletes this domain from the database.  If there is an error, returns the
error, otherwise returns false.

The corresponding FS::cust_svc record will be deleted as well.

=cut

sub delete {
  my $self = shift;

  return "Can't delete a domain which has accounts!"
    if qsearch( 'svc_acct', { 'domsvc' => $self->svcnum } );

  #return "Can't delete a domain with (domain_record) zone entries!"
  #  if qsearch('domain_record', { 'svcnum' => $self->svcnum } );

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  foreach my $domain_record ( reverse $self->domain_record ) {
    my $error = $domain_record->delete;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "can't delete DNS entry: ".
             join(' ', map $domain_record->$_(),
                           qw( reczone recaf rectype recdata )
                 ).
             ":$error";
    }
  }

  my $error = $self->SUPER::delete;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
}

=item replace OLD_RECORD

Replaces OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

sub replace {
  my ( $new, $old ) = ( shift, shift );

  # We absolutely have to have an old vs. new record to make this work.
  $old = $new->replace_old unless defined($old);

  return "Can't change domain - reorder."
    if $old->getfield('domain') ne $new->getfield('domain'); 

  # Better to do it here than to force the caller to remember that svc_domain is weird.
  $new->setfield(action => 'M');
  my $error = $new->SUPER::replace($old);
  return $error if $error;
}

=item suspend

Just returns false (no error) for now.

Called by the suspend method of FS::cust_pkg (see L<FS::cust_pkg>).

=item unsuspend

Just returns false (no error) for now.

Called by the unsuspend method of FS::cust_pkg (see L<FS::cust_pkg>).

=item cancel

Just returns false (no error) for now.

Called by the cancel method of FS::cust_pkg (see L<FS::cust_pkg>).

=item check

Checks all fields to make sure this is a valid domain.  If there is an error,
returns the error, otherwise returns false.  Called by the insert and replace
methods.

Sets any fixed values; see L<FS::part_svc>.

=cut

sub check {
  my $self = shift;

  my $x = $self->setfixed;
  return $x unless ref($x);
  #my $part_svc = $x;

  my $error = $self->ut_numbern('svcnum')
              || $self->ut_numbern('catchall')
  ;
  return $error if $error;

  #hmm
  my $pkgnum;
  if ( $self->svcnum ) {
    my $cust_svc = qsearchs( 'cust_svc', { 'svcnum' => $self->svcnum } );
    $pkgnum = $cust_svc->pkgnum;
  } else {
    $pkgnum = $self->pkgnum;
  }

  my($recref) = $self->hashref;

  #if ( $recref->{domain} =~ /^([\w\-\.]{1,22})\.(com|net|org|edu)$/ ) {
  if ( $recref->{domain} =~ /^([\w\-]{1,63})\.(com|net|org|edu|tv|info|biz)$/ ) {
    $recref->{domain} = "$1.$2";
    $recref->{suffix} ||= $2;
  # hmmmmmmmm.
  } elsif ( $whois_hack && $recref->{domain} =~ /^([\w\-\.]+)\.(\w+)$/ ) {
    $recref->{domain} = "$1.$2";
    # need to match a list of suffixes - no guarantee they're top-level..
  } else {
    return "Illegal domain ". $recref->{domain}.
           " (or unknown registry - try \$whois_hack)";
  }


  if ( $recref->{catchall} ne '' ) {
    my $svc_acct = qsearchs( 'svc_acct', { 'svcnum' => $recref->{catchall} } );
    return "Unknown catchall" unless $svc_acct;
  }

  $self->ut_alphan('suffix')
    or $self->ut_foreign_keyn('registrarnum', 'registrar', 'registrarnum')
    or $self->ut_textn('registrarkey')
    or $self->ut_numbern('setup_date')
    or $self->ut_numbern('renewal_interval')
    or $self->ut_numbern('expiration_date')
    or $self->ut_textn('purpose')
    or $self->SUPER::check;

}

=item domain_record

=cut

sub domain_record {
  my $self = shift;

  my %order = (
    'SOA'   => 1,
    'NS'    => 2,
    'MX'    => 3,
    'CNAME' => 4,
    'A'     => 5,
    'TXT'   => 6,
    'PTR'   => 7,
  );

  my %sort = (
    #'SOA'   => sub { $_[0]->recdata cmp $_[1]->recdata }, #sure hope not though
#    'SOA'   => sub { 0; },
#    'NS'    => sub { 0; },
    'MX'    => sub { my( $a_weight, $a_name ) = split(/\s+/, $_[0]->recdata);
                     my( $b_weight, $b_name ) = split(/\s+/, $_[1]->recdata);
                     $a_weight <=> $b_weight or $a_name cmp $b_name;
                   },
    'CNAME' => sub { $_[0]->reczone cmp $_[1]->reczone },
    'A'     => sub { $_[0]->reczone cmp $_[1]->reczone },

#    'TXT'   => sub { 0; },
    'PTR'   => sub { $_[0]->reczone <=> $_[1]->reczone },
  );

  sort {    $order{$a->rectype} <=> $order{$b->rectype}
         or &{ $sort{$a->rectype} || sub { 0; } }($a, $b)
       }
       qsearch('domain_record', { svcnum => $self->svcnum } );

}

sub catchall_svc_acct {
  my $self = shift;
  if ( $self->catchall ) {
    qsearchs( 'svc_acct', { 'svcnum' => $self->catchall } );
  } else {
    '';
  }
}

=item whois

# Returns the Net::Whois::Domain object (see L<Net::Whois>) for this domain, or
# undef if the domain is not found in whois.

(If $FS::svc_domain::whois_hack is true, returns that in all cases instead.)

=cut

sub whois {
  #$whois_hack or new Net::Whois::Domain $_[0]->domain;
  #$whois_hack or die "whois_hack not set...\n";
}

=item _whois

Depriciated.

=cut

sub _whois {
  die "_whois depriciated";
}

=item submit_internic

Submits a registration email for this domain.

=cut

sub submit_internic {
  #my $self = shift;
  carp "submit_internic depreciated";
}

=back

=head1 BUGS

Delete doesn't send a registration template.

All registries should be supported.

Should change action to a real field.

The $recref stuff in sub check should be cleaned up.

=head1 SEE ALSO

L<FS::svc_Common>, L<FS::Record>, L<FS::Conf>, L<FS::cust_svc>,
L<FS::part_svc>, L<FS::cust_pkg>, L<Net::Whois>, schema.html from the base
documentation, config.html from the base documentation.

=cut

1;


