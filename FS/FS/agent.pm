package FS::agent;

use strict;
use vars qw( @ISA );
#use Crypt::YAPassGen;
use FS::Record qw( dbh qsearch qsearchs );
use FS::cust_main;
use FS::cust_pkg;
use FS::agent_type;
use FS::reg_code;
use FS::TicketSystem;

@ISA = qw( FS::Record );

=head1 NAME

FS::agent - Object methods for agent records

=head1 SYNOPSIS

  use FS::agent;

  $record = new FS::agent \%hash;
  $record = new FS::agent { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

  $agent_type = $record->agent_type;

  $hashref = $record->pkgpart_hashref;
  #may purchase $pkgpart if $hashref->{$pkgpart};

=head1 DESCRIPTION

An FS::agent object represents an agent.  Every customer has an agent.  Agents
can be used to track things like resellers or salespeople.  FS::agent inherits
from FS::Record.  The following fields are currently supported:

=over 4

=item agentnum - primary key (assigned automatically for new agents)

=item agent - Text name of this agent

=item typenum - Agent type.  See L<FS::agent_type>

=item prog - For future use.

=item freq - For future use.

=item disabled - Disabled flag, empty or 'Y'

=item username - Username for the Agent interface

=item _password - Password for the Agent interface

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new agent.  To add the agent to the database, see L<"insert">.

=cut

sub table { 'agent'; }

=item insert

Adds this agent to the database.  If there is an error, returns the error,
otherwise returns false.

=item delete

Deletes this agent from the database.  Only agents with no customers can be
deleted.  If there is an error, returns the error, otherwise returns false.

=cut

sub delete {
  my $self = shift;

  return "Can't delete an agent with customers!"
    if qsearch( 'cust_main', { 'agentnum' => $self->agentnum } );

  $self->SUPER::delete;
}

=item replace OLD_RECORD

Replaces OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=item check

Checks all fields to make sure this is a valid agent.  If there is an error,
returns the error, otherwise returns false.  Called by the insert and replace
methods.

=cut

sub check {
  my $self = shift;

  my $error =
    $self->ut_numbern('agentnum')
      || $self->ut_text('agent')
      || $self->ut_number('typenum')
      || $self->ut_numbern('freq')
      || $self->ut_textn('prog')
  ;
  return $error if $error;

  if ( $self->dbdef_table->column('disabled') ) {
    $error = $self->ut_enum('disabled', [ '', 'Y' ] );
    return $error if $error;
  }

  if ( $self->dbdef_table->column('username') ) {
    $error = $self->ut_alphan('username');
    return $error if $error;
    if ( length($self->username) ) {
      my $conflict = qsearchs('agent', { 'username' => $self->username } );
      return 'duplicate agent username (with '. $conflict->agent. ')'
        if $conflict && $conflict->agentnum != $self->agentnum;
      $error = $self->ut_text('password'); # ut_text... arbitrary choice
    } else {
      $self->_password('');
    }
  }

  return "Unknown typenum!"
    unless $self->agent_type;

  $self->SUPER::check;
}

=item agent_type

Returns the FS::agent_type object (see L<FS::agent_type>) for this agent.

=cut

sub agent_type {
  my $self = shift;
  qsearchs( 'agent_type', { 'typenum' => $self->typenum } );
}

=item pkgpart_hashref

Returns a hash reference.  The keys of the hash are pkgparts.  The value is
true if this agent may purchase the specified package definition.  See
L<FS::part_pkg>.

=cut

sub pkgpart_hashref {
  my $self = shift;
  $self->agent_type->pkgpart_hashref;
}

=item ticketing_queue

Returns the queue name corresponding with the id from the I<ticketing_queueid>
field, or the empty string.

=cut

sub ticketing_queue {
  my $self = shift;
  FS::TicketSystem->queue($self->ticketing_queueid);
};

=item num_prospect_cust_main

Returns the number of prospects (customers with no packages ever ordered) for
this agent.

=cut

sub num_prospect_cust_main {
  shift->num_sql(FS::cust_main->prospect_sql);
}

sub num_sql {
  my( $self, $sql ) = @_;
  my $statement = "SELECT COUNT(*) FROM cust_main WHERE agentnum = ? AND $sql";
  my $sth = dbh->prepare($statement) or die dbh->errstr." preparing $statement";
  $sth->execute($self->agentnum) or die $sth->errstr. "executing $statement";
  $sth->fetchrow_arrayref->[0];
}

=item prospect_cust_main

Returns the prospects (customers with no packages ever ordered) for this agent,
as cust_main objects.

=cut

sub prospect_cust_main {
  shift->cust_main_sql(FS::cust_main->prospect_sql);
}

sub cust_main_sql {
  my( $self, $sql ) = @_;
  qsearch( 'cust_main',
           { 'agentnum' => $self->agentnum },
           '',
           " AND $sql"
  );
}

=item num_active_cust_main

Returns the number of active customers for this agent.

=cut

sub num_active_cust_main {
  shift->num_sql(FS::cust_main->active_sql);
}

=item active_cust_main

Returns the active customers for this agent, as cust_main objects.

=cut

sub active_cust_main {
  shift->cust_main_sql(FS::cust_main->active_sql);
}

=item num_susp_cust_main

Returns the number of suspended customers for this agent.

=cut

sub num_susp_cust_main {
  shift->num_sql(FS::cust_main->susp_sql);
}

=item susp_cust_main

Returns the suspended customers for this agent, as cust_main objects.

=cut

sub susp_cust_main {
  shift->cust_main_sql(FS::cust_main->susp_sql);
}

=item num_cancel_cust_main

Returns the number of cancelled customer for this agent.

=cut

sub num_cancel_cust_main {
  shift->num_sql(FS::cust_main->cancel_sql);
}

=item cancel_cust_main

Returns the cancelled customers for this agent, as cust_main objects.

=cut

sub cancel_cust_main {
  shift->cust_main_sql(FS::cust_main->cancel_sql);
}

=item num_active_cust_pkg

Returns the number of active customer packages for this agent.

=cut

sub num_active_cust_pkg {
  shift->num_pkg_sql(FS::cust_pkg->active_sql);
}

sub num_pkg_sql {
  my( $self, $sql ) = @_;
  my $statement = 
    "SELECT COUNT(*) FROM cust_pkg LEFT JOIN cust_main USING ( custnum )".
    " WHERE agentnum = ? AND $sql";
  my $sth = dbh->prepare($statement) or die dbh->errstr." preparing $statement";
  $sth->execute($self->agentnum) or die $sth->errstr. "executing $statement";
  $sth->fetchrow_arrayref->[0];
}

=item num_susp_cust_pkg

Returns the number of suspended customer packages for this agent.

=cut

sub num_susp_cust_pkg {
  shift->num_pkg_sql(FS::cust_pkg->susp_sql);
}

=item num_cancel_cust_pkg

Returns the number of cancelled customer packages for this agent.

=cut

sub num_cancel_cust_pkg {
  shift->num_pkg_sql(FS::cust_pkg->cancel_sql);
}

=item generate_reg_codes NUM PKGPART_ARRAYREF

Generates the specified number of registration codes, allowing purchase of the
specified package definitions.  Returns an array reference of the newly
generated codes, or a scalar error message.

=cut

#false laziness w/prepay_credit::generate
sub generate_reg_codes {
  my( $self, $num, $pkgparts ) = @_;

  my @codeset = ( 'A'..'Z' );

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my @codes = ();
  for ( 1 ... $num ) {
    my $reg_code = new FS::reg_code {
      'agentnum' => $self->agentnum,
      'code'     => join('', map($codeset[int(rand $#codeset)], (0..7) ) ),
    };
    my $error = $reg_code->insert($pkgparts);
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
    push @codes, $reg_code->code;
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  \@codes;

}

=item num_reg_code

Returns the number of unused registration codes for this agent.

=cut

sub num_reg_code {
  my $self = shift;
  my $sth = dbh->prepare(
    "SELECT COUNT(*) FROM reg_code WHERE agentnum = ?"
  ) or die dbh->errstr;
  $sth->execute($self->agentnum) or die $sth->errstr;
  $sth->fetchrow_arrayref->[0];
}

=item num_prepay_credit

Returns the number of unused prepaid cards for this agent.

=cut

sub num_prepay_credit {
  my $self = shift;
  my $sth = dbh->prepare(
    "SELECT COUNT(*) FROM prepay_credit WHERE agentnum = ?"
  ) or die dbh->errstr;
  $sth->execute($self->agentnum) or die $sth->errstr;
  $sth->fetchrow_arrayref->[0];
}


=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, L<FS::agent_type>, L<FS::cust_main>, L<FS::part_pkg>, 
schema.html from the base documentation.

=cut

1;

