package FS::part_pkg;

use strict;
use vars qw( @ISA $DEBUG );
use FS::Conf;
use FS::Record qw( qsearch qsearchs dbh dbdef );
use FS::pkg_svc;
use FS::part_svc;
use FS::cust_pkg;
use FS::agent_type;
use FS::type_pkgs;

@ISA = qw( FS::Record );

$DEBUG = 0;

=head1 NAME

FS::part_pkg - Object methods for part_pkg objects

=head1 SYNOPSIS

  use FS::part_pkg;

  $record = new FS::part_pkg \%hash
  $record = new FS::part_pkg { 'column' => 'value' };

  $custom_record = $template_record->clone;

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

  @pkg_svc = $record->pkg_svc;

  $svcnum = $record->svcpart;
  $svcnum = $record->svcpart( 'svc_acct' );

=head1 DESCRIPTION

An FS::part_pkg object represents a billing item definition.  FS::part_pkg
inherits from FS::Record.  The following fields are currently supported:

=over 4

=item pkgpart - primary key (assigned automatically for new billing item definitions)

=item pkg - Text name of this billing item definition (customer-viewable)

=item comment - Text name of this billing item definition (non-customer-viewable)

=item setup - Setup fee expression

=item freq - Frequency of recurring fee

=item recur - Recurring fee expression

=item setuptax - Setup fee tax exempt flag, empty or `Y'

=item recurtax - Recurring fee tax exempt flag, empty or `Y'

=item taxclass - Tax class flag

=item plan - Price plan

=item plandata - Price plan data

=item disabled - Disabled flag, empty or `Y'

=back

setup and recur are evaluated as Safe perl expressions.  You can use numbers
just as you would normally.  More advanced semantics are not yet defined.

=head1 METHODS

=over 4 

=item new HASHREF

Creates a new billing item definition.  To add the billing item definition to
the database, see L<"insert">.

=cut

sub table { 'part_pkg'; }

=item clone

An alternate constructor.  Creates a new billing item definition by duplicating
an existing definition.  A new pkgpart is assigned and `(CUSTOM) ' is prepended
to the comment field.  To add the billing item definition to the database, see
L<"insert">.

=cut

sub clone {
  my $self = shift;
  my $class = ref($self);
  my %hash = $self->hash;
  $hash{'pkgpart'} = '';
  $hash{'comment'} = "(CUSTOM) ". $hash{'comment'}
    unless $hash{'comment'} =~ /^\(CUSTOM\) /;
  #new FS::part_pkg ( \%hash ); # ?
  new $class ( \%hash ); # ?
}

=item insert [ , OPTION => VALUE ... ]

Adds this billing item definition to the database.  If there is an error,
returns the error, otherwise returns false.

Currently available options are: I<pkg_svc>, I<primary_svc>, I<cust_pkg> and
I<custnum_ref>.

If I<pkg_svc> is set to a hashref with svcparts as keys and quantities as
values, appropriate FS::pkg_svc records will be inserted.

If I<primary_svc> is set to the svcpart of the primary service, the appropriate
FS::pkg_svc record will be updated.

If I<cust_pkg> is set to a pkgnum of a FS::cust_pkg record (or the FS::cust_pkg
record itself), the object will be updated to point to this package definition.

In conjunction with I<cust_pkg>, if I<custnum_ref> is set to a scalar reference,
the scalar will be updated with the custnum value from the cust_pkg record.

=cut

sub insert {
  my $self = shift;
  my %options = @_;
  warn "FS::part_pkg::insert called on $self with options %options" if $DEBUG;
  
  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $error = $self->SUPER::insert;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  my $conf = new FS::Conf;

  if ( $conf->exists('agent_defaultpkg') ) {
    foreach my $agent_type ( qsearch('agent_type', {} ) ) {
      my $type_pkgs = new FS::type_pkgs({
        'typenum' => $agent_type->typenum,
        'pkgpart' => $self->pkgpart,
      });
      my $error = $type_pkgs->insert;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return $error;
      }
    }
  }

  warn "  inserting pkg_svc records" if $DEBUG;
  my $pkg_svc = $options{'pkg_svc'} || {};
  foreach my $part_svc ( qsearch('part_svc', {} ) ) {
    my $quantity = $pkg_svc->{$part_svc->svcpart} || 0;
    my $primary_svc = $options{'primary_svc'} == $part_svc->svcpart ? 'Y' : '';

    my $pkg_svc = new FS::pkg_svc( {
      'pkgpart'     => $self->pkgpart,
      'svcpart'     => $part_svc->svcpart,
      'quantity'    => $quantity, 
      'primary_svc' => $primary_svc,
    } );
    my $error = $pkg_svc->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  if ( $options{'cust_pkg'} ) {
    warn "  updating cust_pkg record " if $DEBUG;
    my $old_cust_pkg =
      ref($options{'cust_pkg'})
        ? $options{'cust_pkg'}
        : qsearchs('cust_pkg', { pkgnum => $options{'cust_pkg'} } );
    ${ $options{'custnum_ref'} } = $old_cust_pkg->custnum
      if $options{'custnum_ref'};
    my %hash = $old_cust_pkg->hash;
    $hash{'pkgpart'} = $self->pkgpart,
    my $new_cust_pkg = new FS::cust_pkg \%hash;
    local($FS::cust_pkg::disable_agentcheck) = 1;
    my $error = $new_cust_pkg->replace($old_cust_pkg);
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "Error modifying cust_pkg record: $error";
    }
  }

  warn "  commiting transaction" if $DEBUG;
  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';
}

=item delete

Currently unimplemented.

=cut

sub delete {
  return "Can't (yet?) delete package definitions.";
# check & make sure the pkgpart isn't in cust_pkg or type_pkgs?
}

=item replace OLD_RECORD [ , OPTION => VALUE ... ]

Replaces OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

Currently available options are: I<pkg_svc> and I<primary_svc>

If I<pkg_svc> is set to a hashref with svcparts as keys and quantities as
values, the appropriate FS::pkg_svc records will be replace.

If I<primary_svc> is set to the svcpart of the primary service, the appropriate
FS::pkg_svc record will be updated.

=cut

sub replace {
  my( $new, $old ) = ( shift, shift );
  my %options = @_;
  warn "FS::part_pkg::replace called on $new to replace $old ".
       "with options %options"
    if $DEBUG;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  warn "  replacing part_pkg record" if $DEBUG;
  my $error = $new->SUPER::replace($old);
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  warn "  replacing pkg_svc records" if $DEBUG;
  my $pkg_svc = $options{'pkg_svc'} || {};
  foreach my $part_svc ( qsearch('part_svc', {} ) ) {
    my $quantity = $pkg_svc->{$part_svc->svcpart} || 0;
    my $primary_svc = $options{'primary_svc'} == $part_svc->svcpart ? 'Y' : '';

    my $old_pkg_svc = qsearchs('pkg_svc', {
      'pkgpart' => $old->pkgpart,
      'svcpart' => $part_svc->svcpart,
    } );
    my $old_quantity = $old_pkg_svc ? $old_pkg_svc->quantity : 0;
    my $old_primary_svc =
      ( $old_pkg_svc && $old_pkg_svc->dbdef_table->column('primary_svc') )
        ? $old_pkg_svc->primary_svc
        : '';
    next unless $old_quantity != $quantity || $old_primary_svc ne $primary_svc;
  
    my $new_pkg_svc = new FS::pkg_svc( {
      'pkgpart'     => $new->pkgpart,
      'svcpart'     => $part_svc->svcpart,
      'quantity'    => $quantity, 
      'primary_svc' => $primary_svc,
    } );
    my $error = $old_pkg_svc
                  ? $new_pkg_svc->replace($old_pkg_svc)
                  : $new_pkg_svc->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  warn "  commiting transaction" if $DEBUG;
  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  '';
}

=item check

Checks all fields to make sure this is a valid billing item definition.  If
there is an error, returns the error, otherwise returns false.  Called by the
insert and replace methods.

=cut

sub check {
  my $self = shift;

  for (qw(setup recur)) { $self->set($_=>0) if $self->get($_) =~ /^\s*$/; }

  my $conf = new FS::Conf;
  if ( $conf->exists('safe-part_pkg') ) {

    my $error = $self->ut_anything('setup')
                || $self->ut_anything('recur');
    return $error if $error;

    my $s = $self->setup;

    $s =~ /^\s*\d*\.?\d*\s*$/

      or $s =~ /^my \$d = \$cust_pkg->bill || \$time; \$d += 86400 \* \s*\d+\s*; \$cust_pkg->bill\(\$d\); \$cust_pkg_mod_flag=1; \s*\d*\.?\d*\s*$/

      or do {
        #log!
        return "illegal setup: $s";
      };

    my $r = $self->recur;

    $r =~ /^\s*\d*\.?\d*\s*$/

      #or $r =~ /^\$sdate += 86400 \* \s*\d+\s*; \s*\d*\.?\d*\s*$/

      or $r =~ /^my \$mnow = \$sdate; my \(\$sec,\$min,\$hour,\$mday,\$mon,\$year\) = \(localtime\(\$sdate\) \)\[0,1,2,3,4,5\]; my \$mstart = timelocal\(0,0,0,1,\$mon,\$year\); my \$mend = timelocal\(0,0,0,1, \$mon == 11 \? 0 : \$mon\+1, \$year\+\(\$mon==11\)\); \$sdate = \$mstart; \( \$part_pkg->freq \- 1 \) \* \d*\.?\d* \/ \$part_pkg\-\>freq \+ \d*\.?\d* \/ \$part_pkg\-\>freq \* \(\$mend\-\$mnow\) \/ \(\$mend\-\$mstart\) ;\s*$/

      or $r =~ /^my \$mnow = \$sdate; my \(\$sec,\$min,\$hour,\$mday,\$mon,\$year\) = \(localtime\(\$sdate\) \)\[0,1,2,3,4,5\]; \$sdate = timelocal\(0,0,0,1,\$mon,\$year\); \s*\d*\.?\d*\s*;\s*$/

      or $r =~ /^my \$error = \$cust_pkg\->cust_main\->credit\( \s*\d*\.?\d*\s* \* scalar\(\$cust_pkg\->cust_main\->referral_cust_main_ncancelled\(\s*\d+\s*\)\), "commission" \); die \$error if \$error; \s*\d*\.?\d*\s*;\s*$/

      or $r =~ /^my \$error = \$cust_pkg\->cust_main\->credit\( \s*\d*\.?\d*\s* \* scalar\(\$cust_pkg\->cust_main->referral_cust_pkg\(\s*\d+\s*\)\), "commission" \); die \$error if \$error; \s*\d*\.?\d*\s*;\s*$/

      or $r =~ /^my \$error = \$cust_pkg\->cust_main\->credit\( \s*\d*\.?\d*\s* \* scalar\( grep \{ my \$pkgpart = \$_\->pkgpart; grep \{ \$_ == \$pkgpart \} \(\s*(\s*\d+,\s*)*\s*\) \} \$cust_pkg\->cust_main->referral_cust_pkg\(\s*\d+\s*\)\), "commission" \); die \$error if \$error; \s*\d*\.?\d*\s*;\s*$/

      or $r =~ /^my \$hours = \$cust_pkg\->seconds_since\(\$cust_pkg\->bill \|\| 0\) \/ 3600 \- \s*\d*\.?\d*\s*; \$hours = 0 if \$hours < 0; \s*\d*\.?\d*\s* \+ \s*\d*\.?\d*\s* \* \$hours;\s*$/

      or $r =~ /^my \$min = \$cust_pkg\->seconds_since\(\$cust_pkg\->bill \|\| 0\) \/ 60 \- \s*\d*\.?\d*\s*; \$min = 0 if \$min < 0; \s*\d*\.?\d*\s* \+ \s*\d*\.?\d*\s* \* \$min;\s*$/

      or $r =~ /^my \$last_bill = \$cust_pkg\->last_bill; my \$hours = \$cust_pkg\->seconds_since_sqlradacct\(\$last_bill, \$sdate \) \/ 3600 - \s*\d\.?\d*\s*; \$hours = 0 if \$hours < 0; my \$input = \$cust_pkg\->attribute_since_sqlradacct\(\$last_bill, \$sdate, "AcctInputOctets" \) \/ 1048576; my \$output = \$cust_pkg\->attribute_since_sqlradacct\(\$last_bill, \$sdate, "AcctOutputOctets" \) \/ 1048576; my \$total = \$input \+ \$output \- \s*\d\.?\d*\s*; \$total = 0 if \$total < 0; my \$input = \$input - \s*\d\.?\d*\s*; \$input = 0 if \$input < 0; my \$output = \$output - \s*\d\.?\d*\s*; \$output = 0 if \$output < 0; \s*\d\.?\d*\s* \+ \s*\d\.?\d*\s* \* \$hours \+ \s*\d\.?\d*\s* \* \$input \+ \s*\d\.?\d*\s* \* \$output \+ \s*\d\.?\d*\s* \* \$total *;\s*$/

      or do {
        #log!
        return "illegal recur: $r";
      };

  }

  if ( $self->dbdef_table->column('freq')->type =~ /(int)/i ) {
    my $error = $self->ut_number('freq');
    return $error if $error;
  } else {
    $self->freq =~ /^(\d+[dw]?)$/
      or return "Illegal or empty freq: ". $self->freq;
    $self->freq($1);
  }

    $self->ut_numbern('pkgpart')
      || $self->ut_text('pkg')
      || $self->ut_text('comment')
      || $self->ut_anything('setup')
      || $self->ut_anything('recur')
      || $self->ut_alphan('plan')
      || $self->ut_anything('plandata')
      || $self->ut_enum('setuptax', [ '', 'Y' ] )
      || $self->ut_enum('recurtax', [ '', 'Y' ] )
      || $self->ut_textn('taxclass')
      || $self->ut_enum('disabled', [ '', 'Y' ] )
    ;
}

=item pkg_svc

Returns all FS::pkg_svc objects (see L<FS::pkg_svc>) for this package
definition (with non-zero quantity).

=cut

sub pkg_svc {
  my $self = shift;
  grep { $_->quantity } qsearch( 'pkg_svc', { 'pkgpart' => $self->pkgpart } );
}

=item svcpart [ SVCDB ]

Returns the svcpart of the primary service definition (see L<FS::part_svc>)
associated with this billing item definition (see L<FS::pkg_svc>).  Returns
false if there not a primary service definition or exactly one service
definition with quantity 1, or if SVCDB is specified and does not match the
svcdb of the service definition, 

=cut

sub svcpart {
  my $self = shift;
  my $svcdb = scalar(@_) ? shift : '';
  my @svcdb_pkg_svc =
    grep { ( $svcdb eq $_->part_svc->svcdb || !$svcdb ) } $self->pkg_svc;
  my @pkg_svc = ();
  @pkg_svc = grep { $_->primary_svc =~ /^Y/i } @svcdb_pkg_svc
    if dbdef->table('pkg_svc')->column('primary_svc');
  @pkg_svc = grep {$_->quantity == 1 } @svcdb_pkg_svc
    unless @pkg_svc;
  return '' if scalar(@pkg_svc) != 1;
  $pkg_svc[0]->svcpart;
}

=item payby

Returns a list of the acceptable payment types for this package.  Eventually
this should come out of a database table and be editable, but currently has the
following logic instead;

If the package has B<0> setup and B<0> recur, the single item B<BILL> is
returned, otherwise, the single item B<CARD> is returned.

(CHEK?  LEC?  Probably shouldn't accept those by default, prone to abuse)

=cut

sub payby {
  my $self = shift;
  #if ( $self->setup == 0 && $self->recur == 0 ) {
  if (    $self->setup =~ /^\s*0+(\.0*)?\s*$/
       && $self->recur =~ /^\s*0+(\.0*)?\s*$/ ) {
    ( 'BILL' );
  } else {
    ( 'CARD' );
  }
}

=back

=head1 BUGS

The delete method is unimplemented.

setup and recur semantics are not yet defined (and are implemented in
FS::cust_bill.  hmm.).

=head1 SEE ALSO

L<FS::Record>, L<FS::cust_pkg>, L<FS::type_pkgs>, L<FS::pkg_svc>, L<Safe>.
schema.html from the base documentation.

=cut

1;

