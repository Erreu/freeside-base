package FS::access_user;

use strict;
use base qw( FS::m2m_Common FS::option_Common ); 
use vars qw( $DEBUG $me $conf $htpasswd_file );
use FS::UID;
use FS::Conf;
use FS::Record qw( qsearch qsearchs dbh );
use FS::access_user_pref;
use FS::access_usergroup;
use FS::agent;
use FS::cust_main;
use FS::sales;
use FS::sched_item;

$DEBUG = 0;
$me = '[FS::access_user]';

#kludge htpasswd for now (i hope this bootstraps okay)
FS::UID->install_callback( sub {
  $conf = new FS::Conf;
  $htpasswd_file = $conf->base_dir. '/htpasswd';
} );

=head1 NAME

FS::access_user - Object methods for access_user records

=head1 SYNOPSIS

  use FS::access_user;

  $record = new FS::access_user \%hash;
  $record = new FS::access_user { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::access_user object represents an internal access user.  FS::access_user
inherits from FS::Record.  The following fields are currently supported:

=over 4

=item usernum - primary key

=item username - 

=item _password - 

=item last -

=item first -

=item disabled - empty or 'Y'

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new internal access user.  To add the user to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'access_user'; }

sub _option_table    { 'access_user_pref'; }
sub _option_namecol  { 'prefname'; }
sub _option_valuecol { 'prefvalue'; }

=item insert

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

sub insert {
  my $self = shift;

  my $error = $self->check;
  return $error if $error;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  $error = $self->htpasswd_kludge();
  if ( $error ) {
    $dbh->rollback or die $dbh->errstr if $oldAutoCommit;
    return $error;
  }

  $error = $self->SUPER::insert(@_);

  if ( $error ) {
    $dbh->rollback or die $dbh->errstr if $oldAutoCommit;

    #make sure it isn't a dup username?  or you could nuke people's passwords
    #blah.  really just should do our own login w/cookies
    #and auth out of the db in the first place
    #my $hterror = $self->htpasswd_kludge('-D');
    #$error .= " - additionally received error cleaning up htpasswd file: $hterror"
    return $error;

  } else {
    $dbh->commit or die $dbh->errstr if $oldAutoCommit;
    '';
  }

}

sub htpasswd_kludge {
  my $self = shift;

  return '' if $self->is_system_user;

  unshift @_, '-c' unless -e $htpasswd_file;
  if ( 
       system('htpasswd', '-b', @_,
                          $htpasswd_file,
                          $self->username,
                          $self->_password,
             ) == 0
     )
  {
    return '';
  } else {
    return 'htpasswd exited unsucessfully';
  }
}

=item delete

Delete this record from the database.

=cut

sub delete {
  my $self = shift;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $error =
       $self->SUPER::delete(@_)
    || $self->htpasswd_kludge('-D')
  ;

  if ( $error ) {
    $dbh->rollback or die $dbh->errstr if $oldAutoCommit;
    return $error;
  } else {
    $dbh->commit or die $dbh->errstr if $oldAutoCommit;
    '';
  }

}

=item replace OLD_RECORD

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

sub replace {
  my $new = shift;

  my $old = ( ref($_[0]) eq ref($new) )
              ? shift
              : $new->replace_old;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  if ( $new->_password ne $old->_password ) {
    my $error = $new->htpasswd_kludge();
    if ( $error ) {
      $dbh->rollback or die $dbh->errstr if $oldAutoCommit;
      return $error;
    }
  } elsif ( $old->disabled && !$new->disabled
              && $new->_password =~ /changeme/i ) {
    return "Must change password when enabling this account";
  }

  my $error = $new->SUPER::replace($old, @_);

  if ( $error ) {
    $dbh->rollback or die $dbh->errstr if $oldAutoCommit;
    return $error;
  } else {
    $dbh->commit or die $dbh->errstr if $oldAutoCommit;
    '';
  }

}

=item check

Checks all fields to make sure this is a valid internal access user.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

# the check method should currently be supplied - FS::Record contains some
# data checking routines

sub check {
  my $self = shift;

  my $error = 
    $self->ut_numbern('usernum')
    || $self->ut_alpha_lower('username')
    || $self->ut_text('_password')
    || $self->ut_text('last')
    || $self->ut_text('first')
    || $self->ut_foreign_keyn('user_custnum', 'cust_main', 'custnum')
    || $self->ut_foreign_keyn('report_salesnum', 'sales', 'salesnum')
    || $self->ut_enum('disabled', [ '', 'Y' ] )
  ;
  return $error if $error;

  $self->SUPER::check;
}

=item name

Returns a name string for this user: "Last, First".

=cut

sub name {
  my $self = shift;
  return $self->username
    if $self->get('last') eq 'Lastname' && $self->first eq 'Firstname';
  return $self->get('last'). ', '. $self->first;
}

=item user_cust_main

Returns the FS::cust_main object (see L<FS::cust_main>), if any, for this
user.

=cut

sub user_cust_main {
  my $self = shift;
  qsearchs( 'cust_main', { 'custnum' => $self->user_custnum } );
}

=item report_sales

Returns the FS::sales object (see L<FS::sales>), if any, for this
user.

=cut

sub report_sales {
  my $self = shift;
  qsearchs( 'sales', { 'salesnum' => $self->report_salesnum } );
}

=item access_usergroup

Returns links to the the groups this user is a part of, as FS::access_usergroup
objects (see L<FS::access_usergroup>).

=cut

sub access_usergroup {
  my $self = shift;
  qsearch( 'access_usergroup', { 'usernum' => $self->usernum } );
}

#=item access_groups
#
#=cut
#
#sub access_groups {
#
#}
#
#=item access_groupnames
#
#=cut
#
#sub access_groupnames {
#
#}

=item num_agents

Returns the number of agents this user can view (via group membership).

=cut

sub num_agents {
  my $self = shift;
  $self->scalar_sql(
    'SELECT COUNT(DISTINCT agentnum) FROM access_usergroup
                                     JOIN access_groupagent USING ( groupnum )
       WHERE usernum = ?',
    $self->usernum,
  );
}

=item agentnums 

Returns a list of agentnums this user can view (via group membership).

=cut

sub agentnums {
  my $self = shift;
  my $sth = dbh->prepare(
    "SELECT DISTINCT agentnum FROM access_usergroup
                              JOIN access_groupagent USING ( groupnum )
       WHERE usernum = ?"
  ) or die dbh->errstr;
  $sth->execute($self->usernum) or die $sth->errstr;
  map { $_->[0] } @{ $sth->fetchall_arrayref };
}

=item agentnums_href

Returns a hashref of agentnums this user can view.

=cut

sub agentnums_href {
  my $self = shift;
  scalar( { map { $_ => 1 } $self->agentnums } );
}

=item agentnums_sql [ HASHREF | OPTION => VALUE ... ]

Returns an sql fragement to select only agentnums this user can view.

Options are passed as a hashref or a list.  Available options are:

=over 4

=item null

The frament will also allow the selection of null agentnums.

=item null_right

The fragment will also allow the selection of null agentnums if the current
user has the provided access right

=item table

Optional table name in which agentnum is being checked.  Sometimes required to
resolve 'column reference "agentnum" is ambiguous' errors.

=item viewall_right

All agents will be viewable if the current user has the provided access right.
Defaults to 'View customers of all agents'.

=back

=cut

sub agentnums_sql {
  my( $self ) = shift;
  my %opt = ref($_[0]) ? %{$_[0]} : @_;

  my $agentnum = $opt{'table'} ? $opt{'table'}.'.agentnum' : 'agentnum';

  my @or = ();

  my $viewall_right = $opt{'viewall_right'} || 'View customers of all agents';
  if ( $self->access_right($viewall_right) ) {
    push @or, "$agentnum IS NOT NULL";
  } else {
    my @agentnums = $self->agentnums;
    push @or, "$agentnum IN (". join(',', @agentnums). ')'
      if @agentnums;
  }

  push @or, "$agentnum IS NULL"
    if $opt{'null'}
    || ( $opt{'null_right'} && $self->access_right($opt{'null_right'}) );

  return ' 1 = 0 ' unless scalar(@or);
  '( '. join( ' OR ', @or ). ' )';

}

=item agentnum

Returns true if the user can view the specified agent.

Also accepts optional hashref cache, to avoid redundant database calls.

=cut

sub agentnum {
  my( $self, $agentnum, $cache ) = @_;
  $cache ||= {};
  return $cache->{$self->usernum}->{$agentnum}
    if $cache->{$self->usernum}->{$agentnum};
  my $sth = dbh->prepare(
    "SELECT COUNT(*) FROM access_usergroup
                     JOIN access_groupagent USING ( groupnum )
       WHERE usernum = ? AND agentnum = ?"
  ) or die dbh->errstr;
  $sth->execute($self->usernum, $agentnum) or die $sth->errstr;
  $cache->{$self->usernum}->{$agentnum} = $sth->fetchrow_arrayref->[0];
  $sth->finish;
  return $cache->{$self->usernum}->{$agentnum};
}

=item agents [ HASHREF | OPTION => VALUE ... ]

Returns the list of agents this user can view (via group membership), as
FS::agent objects.  Accepts the same options as the agentnums_sql method.

=cut

sub agents {
  my $self = shift;
  qsearch({
    'table'     => 'agent',
    'hashref'   => { disabled=>'' },
    'extra_sql' => ' AND '. $self->agentnums_sql(@_),
    'order_by'  => 'ORDER BY agent',
  });
}

=item access_users [ HASHREF | OPTION => VALUE ... ]

Returns an array of FS::access_user objects, one for each non-disabled 
access_user in the system that shares an agent (via group membership) with 
the invoking object.  Regardless of options and agents, will always at
least return the invoking user and any users who have viewall_right.

Accepts the following options:

=over 4

=item table

Only return users who appear in the usernum field of this table

=item disabled

Include disabled users if true (defaults to false)

=item viewall_right

All users will be returned if the current user has the provided 
access right, regardless of agents (other filters still apply.)  
Defaults to 'View customers of all agents'

=cut

#Leaving undocumented until such time as this functionality is actually used
#
#=item null
#
#Users with no agents will be returned.
#
#=item null_right
#
#Users with no agents will be returned if the current user has the provided
#access right.

sub access_users {
  my $self = shift;
  my %opt = ref($_[0]) ? %{$_[0]} : @_;
  my $table = $opt{'table'};
  my $search = { 'table' => 'access_user' };
  $search->{'hashref'} = $opt{'disabled'} ? {} : { 'disabled' => '' };
  $search->{'addl_from'} = "INNER JOIN $table ON (access_user.usernum = $table.usernum)"
    if $table;
  my @access_users = qsearch($search);
  my $viewall_right = $opt{'viewall_right'} || 'View customers of a￼ll agents';
  return @access_users if $self->access_right($viewall_right);
  #filter for users with agents $self can view
  my @out;
  my $agentnum_cache = {};
ACCESS_USER:
  foreach my $access_user (@access_users) {
    # you can always view yourself, regardless of agents,
    # and you can always view someone who can view you, 
    # since they might have affected your customers
    if ( ($self->usernum eq $access_user->usernum) 
         || $access_user->access_right($viewall_right)
    ) {
      push(@out,$access_user);
      next;
    }
    # if user has no agents, you need null or null_right to view
    my @agents = $access_user->agents('viewall_right'=>'NONE'); #handled viewall_right above
    if (!@agents) {
      if ( $opt{'null'} ||
           ( $opt{'null_right'} && $self->access_right($opt{'null_right'}) )
      ) {
        push(@out,$access_user);
      }
      next;
    }
    # otherwise, you need an agent in common
    foreach my $agent (@agents) {
      if ($self->agentnum($agent->agentnum,$agentnum_cache)) {
        push(@out,$access_user);
        next ACCESS_USER;
      }
    }
  }
  return @out;
}

=item access_users_hashref  [ HASHREF | OPTION => VALUE ... ]

Accepts same options as L</access_users>.  Returns a hashref of
users, with keys of usernum and values of username.

=cut

sub access_users_hashref {
  my $self = shift;
  my %access_users = map { $_->usernum => $_->username } 
                       $self->access_users(@_);
  return \%access_users;
}

=item access_right RIGHTNAME | LISTREF

Given a right name or a list reference of right names, returns true if this
user has this right, or, for a list, one of the rights (currently via group
membership, eventually also via user overrides).

=cut

sub access_right {
  my( $self, $rightname ) = @_;

  $rightname = [ $rightname ] unless ref($rightname);

  warn "$me access_right called on ". join(', ', @$rightname). "\n"
    if $DEBUG;

  #some caching of ACL requests for low-hanging fruit perf improvement
  #since we get a new $CurrentUser object each page view there shouldn't be any
  #issues with stickiness
  if ( $self->{_ACLcache} ) {

    unless ( grep !exists($self->{_ACLcache}{$_}), @$rightname ) {
      warn "$me ACL cache hit for ". join(', ', @$rightname). "\n"
        if $DEBUG;
      return scalar( grep $self->{_ACLcache}{$_}, @$rightname );
    }

    warn "$me ACL cache miss for ". join(', ', @$rightname). "\n"
      if $DEBUG;

  } else {

    warn "initializing ACL cache\n"
      if $DEBUG;
    $self->{_ACLcache} = {};

  }

  my $has_right = ' rightname IN ('. join(',', map '?', @$rightname ). ') ';

  my $sth = dbh->prepare("
    SELECT groupnum FROM access_usergroup
                    LEFT JOIN access_group USING ( groupnum )
                    LEFT JOIN access_right
                         ON ( access_group.groupnum = access_right.rightobjnum )
      WHERE usernum = ?
        AND righttype = 'FS::access_group'
        AND $has_right
      LIMIT 1
  ") or die dbh->errstr;
  $sth->execute($self->usernum, @$rightname) or die $sth->errstr;
  my $row = $sth->fetchrow_arrayref;

  my $return = $row ? $row->[0] : '';

  #just caching the single-rightname hits should be enough of a win for now
  if ( scalar(@$rightname) == 1 ) {
    $self->{_ACLcache}{${$rightname}[0]} = $return;
  }

  $return;

}

=item refund_rights PAYBY

Accepts payment $payby (BILL,CASH,MCRD,MCHK,CARD,CHEK) and returns a
list of the refund rights associated with that $payby.

Returns empty list if $payby wasn't recognized.

=cut

sub refund_rights {
  my $self = shift;
  my $payby = shift;
  my @rights = ();
  push @rights, 'Post refund'                if $payby =~ /^(BILL|CASH|MCRD|MCHK)$/;
  push @rights, 'Post check refund'          if $payby eq 'BILL';
  push @rights, 'Post cash refund '          if $payby eq 'CASH';
  push @rights, 'Refund payment'             if $payby =~ /^(CARD|CHEK)$/;
  push @rights, 'Refund credit card payment' if $payby eq 'CARD';
  push @rights, 'Refund Echeck payment'      if $payby eq 'CHEK';
  return @rights;
}

=item refund_access_right PAYBY

Returns true if user has L</access_right> for any L</refund_rights>
for the specified payby.

=cut

sub refund_access_right {
  my $self = shift;
  my $payby = shift;
  my @rights = $self->refund_rights($payby);
  return '' unless @rights;
  return $self->access_right(\@rights);
}

=item default_customer_view

Returns the default customer view for this user, from the 
"default_customer_view" user preference, the "cust_main-default_view" config,
or the hardcoded default, "basics" (formerly "jumbo" prior to 3.0).

=cut

sub default_customer_view {
  my $self = shift;

  $self->option('default_customer_view')
    || $conf->config('cust_main-default_view')
    || 'basics'; #s/jumbo/basics/ starting with 3.0

}

=item spreadsheet_format [ OVERRIDE ]

Returns a hashref of this user's Excel spreadsheet download settings:
'extension' (xls or xlsx), 'class' (Spreadsheet::WriteExcel or
Excel::Writer::XLSX), and 'mime_type'.  If OVERRIDE is 'XLS' or 'XLSX',
use that instead of the user's setting.

=cut

# is there a better place to put this?
my %formats = (
  XLS => {
    extension => '.xls',
    class => 'Spreadsheet::WriteExcel',
    mime_type => 'application/vnd.ms-excel',
  },
  XLSX => {
    extension => '.xlsx',
    class => 'Excel::Writer::XLSX',
    mime_type => # it's on wikipedia, it must be true
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  }
);

sub spreadsheet_format {
  my $self = shift;
  my $override = shift;

  my $f =  $override
        || $self->option('spreadsheet_format') 
        || $conf->config('spreadsheet_format')
        || 'XLS';

  $formats{$f};
}

=item is_system_user

Returns true if this user has the name of a known system account.  These 
users will not appear in the htpasswd file and can't have passwords set.

=cut

sub is_system_user {
  my $self = shift;
  return grep { $_ eq $self->username } ( qw(
    fs_queue
    fs_daily
    fs_selfservice
    fs_signup
    fs_bootstrap
    fs_selfserv
    fs_api
) );
}

sub sched_item {
  my $self = shift;
  qsearch( 'sched_item', { 'usernum' => $self->usernum } );
}

=item locale

=cut

sub locale {
  my $self = shift;
  return $self->{_locale} if exists($self->{_locale});
  $self->{_locale} = $self->option('locale');
}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut

1;

