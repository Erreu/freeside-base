package FS::svc_acct;

use strict;
use vars qw( @ISA $DEBUG $me $conf $skip_fuzzyfiles
             $dir_prefix @shells $usernamemin
             $usernamemax $passwordmin $passwordmax
             $username_ampersand $username_letter $username_letterfirst
             $username_noperiod $username_nounderscore $username_nodash
             $username_uppercase $username_percent
             $password_noampersand $password_noexclamation
             $welcome_template $welcome_from
             $welcome_subject $welcome_subject_template $welcome_mimetype
             $warning_template $warning_from $warning_subject $warning_mimetype
             $warning_cc
             $smtpmachine
             $radius_password $radius_ip
             $dirhash
             @saltset @pw_set );
use Carp;
use Fcntl qw(:flock);
use Date::Format;
use Crypt::PasswdMD5 1.2;
use Data::Dumper;
use FS::UID qw( datasrc driver_name );
use FS::Conf;
use FS::Record qw( qsearch qsearchs fields dbh dbdef );
use FS::Msgcat qw(gettext);
use FS::UI::bytecount;
use FS::svc_Common;
use FS::cust_svc;
use FS::part_svc;
use FS::svc_acct_pop;
use FS::cust_main_invoice;
use FS::svc_domain;
use FS::raddb;
use FS::queue;
use FS::radius_usergroup;
use FS::export_svc;
use FS::part_export;
use FS::svc_forward;
use FS::svc_www;
use FS::cdr;

@ISA = qw( FS::svc_Common );

$DEBUG = 0;
$me = '[FS::svc_acct]';

#ask FS::UID to run this stuff for us later
$FS::UID::callback{'FS::svc_acct'} = sub { 
  $conf = new FS::Conf;
  $dir_prefix = $conf->config('home');
  @shells = $conf->config('shells');
  $usernamemin = $conf->config('usernamemin') || 2;
  $usernamemax = $conf->config('usernamemax');
  $passwordmin = $conf->config('passwordmin') || 6;
  $passwordmax = $conf->config('passwordmax') || 8;
  $username_letter = $conf->exists('username-letter');
  $username_letterfirst = $conf->exists('username-letterfirst');
  $username_noperiod = $conf->exists('username-noperiod');
  $username_nounderscore = $conf->exists('username-nounderscore');
  $username_nodash = $conf->exists('username-nodash');
  $username_uppercase = $conf->exists('username-uppercase');
  $username_ampersand = $conf->exists('username-ampersand');
  $username_percent = $conf->exists('username-percent');
  $password_noampersand = $conf->exists('password-noexclamation');
  $password_noexclamation = $conf->exists('password-noexclamation');
  $dirhash = $conf->config('dirhash') || 0;
  if ( $conf->exists('welcome_email') ) {
    $welcome_template = new Text::Template (
      TYPE   => 'ARRAY',
      SOURCE => [ map "$_\n", $conf->config('welcome_email') ]
    ) or warn "can't create welcome email template: $Text::Template::ERROR";
    $welcome_from = $conf->config('welcome_email-from'); # || 'your-isp-is-dum'
    $welcome_subject = $conf->config('welcome_email-subject') || 'Welcome';
    $welcome_subject_template = new Text::Template (
      TYPE   => 'STRING',
      SOURCE => $welcome_subject,
    ) or warn "can't create welcome email subject template: $Text::Template::ERROR";
    $welcome_mimetype = $conf->config('welcome_email-mimetype') || 'text/plain';
  } else {
    $welcome_template = '';
    $welcome_from = '';
    $welcome_subject = '';
    $welcome_mimetype = '';
  }
  if ( $conf->exists('warning_email') ) {
    $warning_template = new Text::Template (
      TYPE   => 'ARRAY',
      SOURCE => [ map "$_\n", $conf->config('warning_email') ]
    ) or warn "can't create warning email template: $Text::Template::ERROR";
    $warning_from = $conf->config('warning_email-from'); # || 'your-isp-is-dum'
    $warning_subject = $conf->config('warning_email-subject') || 'Warning';
    $warning_mimetype = $conf->config('warning_email-mimetype') || 'text/plain';
    $warning_cc = $conf->config('warning_email-cc');
  } else {
    $warning_template = '';
    $warning_from = '';
    $warning_subject = '';
    $warning_mimetype = '';
    $warning_cc = '';
  }
  $smtpmachine = $conf->config('smtpmachine');
  $radius_password = $conf->config('radius-password') || 'Password';
  $radius_ip = $conf->config('radius-ip') || 'Framed-IP-Address';
  @pw_set = ( 'A'..'Z' ) if $conf->exists('password-generated-allcaps');
};

@saltset = ( 'a'..'z' , 'A'..'Z' , '0'..'9' , '.' , '/' );
@pw_set = ( 'a'..'z', 'A'..'Z', '0'..'9', '(', ')', '#', '!', '.', ',' );

sub _cache {
  my $self = shift;
  my ( $hashref, $cache ) = @_;
  if ( $hashref->{'svc_acct_svcnum'} ) {
    $self->{'_domsvc'} = FS::svc_domain->new( {
      'svcnum'   => $hashref->{'domsvc'},
      'domain'   => $hashref->{'svc_acct_domain'},
      'catchall' => $hashref->{'svc_acct_catchall'},
    } );
  }
}

=head1 NAME

FS::svc_acct - Object methods for svc_acct records

=head1 SYNOPSIS

  use FS::svc_acct;

  $record = new FS::svc_acct \%hash;
  $record = new FS::svc_acct { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

  $error = $record->suspend;

  $error = $record->unsuspend;

  $error = $record->cancel;

  %hash = $record->radius;

  %hash = $record->radius_reply;

  %hash = $record->radius_check;

  $domain = $record->domain;

  $svc_domain = $record->svc_domain;

  $email = $record->email;

  $seconds_since = $record->seconds_since($timestamp);

=head1 DESCRIPTION

An FS::svc_acct object represents an account.  FS::svc_acct inherits from
FS::svc_Common.  The following fields are currently supported:

=over 4

=item svcnum - primary key (assigned automatcially for new accounts)

=item username

=item _password - generated if blank

=item sec_phrase - security phrase

=item popnum - Point of presence (see L<FS::svc_acct_pop>)

=item uid

=item gid

=item finger - GECOS

=item dir - set automatically if blank (and uid is not)

=item shell

=item quota - (unimplementd)

=item slipip - IP address

=item seconds - 

=item upbytes - 

=item downbytes - 

=item totalbytes - 

=item domsvc - svcnum from svc_domain

=item radius_I<Radius_Attribute> - I<Radius-Attribute> (reply)

=item rc_I<Radius_Attribute> - I<Radius-Attribute> (check)

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new account.  To add the account to the database, see L<"insert">.

=cut

sub table_info {
  {
    'name'   => 'Account',
    'longname_plural' => 'Access accounts and mailboxes',
    'sorts' => [ 'username', 'uid', ],
    'display_weight' => 10,
    'cancel_weight'  => 50, 
    'fields' => {
        'dir'       => 'Home directory',
        'uid'       => {
                         label     => 'UID',
		         def_label => 'UID (set to fixed and blank for no UIDs)',
		         type      => 'text',
		       },
        'slipip'    => 'IP address',
    #    'popnum'    => qq!<A HREF="$p/browse/svc_acct_pop.cgi/">POP number</A>!,
        'popnum'    => {
                         label => 'Access number',
                         type => 'select',
                         select_table => 'svc_acct_pop',
                         select_key   => 'popnum',
                         select_label => 'city',
                         disable_select => 1,
                       },
        'username'  => {
                         label => 'Username',
                         type => 'text',
                         disable_default => 1,
                         disable_fixed => 1,
                         disable_select => 1,
                       },
        'quota'     => { 
                         label => 'Quota',
                         type => 'text',
                         disable_inventory => 1,
                         disable_select => 1,
                       },
        '_password' => 'Password',
        'gid'       => {
                         label     => 'GID',
		         def_label => 'GID (when blank, defaults to UID)',
		         type      => 'text',
		       },
        'shell'     => {
                         #desc =>'Shell (all service definitions should have a default or fixed shell that is present in the <b>shells</b> configuration file, set to blank for no shell tracking)',
		         label    => 'Shell',
                         def_label=> 'Shell (set to blank for no shell tracking)',
                         type     =>'select',
                         select_list => [ $conf->config('shells') ],
                         disable_inventory => 1,
                         disable_select => 1,
                       },
        'finger'    => 'Real name (GECOS)',
        'domsvc'    => {
                         label     => 'Domain',
                         #def_label => 'svcnum from svc_domain',
                         type      => 'select',
                         select_table => 'svc_domain',
                         select_key   => 'svcnum',
                         select_label => 'domain',
                         disable_inventory => 1,

                       },
        'usergroup' => {
                         label => 'RADIUS groups',
                         type  => 'radius_usergroup_selector',
                         disable_inventory => 1,
                         disable_select => 1,
                       },
        'seconds'   => { label => 'Seconds',
                         type  => 'text',
                         disable_inventory => 1,
                         disable_select => 1,
                       },
        'upbytes'   => { label => 'Upload',
                         type  => 'text',
                         disable_inventory => 1,
                         disable_select => 1,
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
        'downbytes' => { label => 'Download',
                         type  => 'text',
                         disable_inventory => 1,
                         disable_select => 1,
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
        'totalbytes'=> { label => 'Total up and download',
                         type  => 'text',
                         disable_inventory => 1,
                         disable_select => 1,
                         'format' => \&FS::UI::bytecount::display_bytecount,
                         'parse' => \&FS::UI::bytecount::parse_bytecount,
                       },
        'seconds_threshold'   => { label => 'Seconds threshold',
                                   type  => 'text',
                                   disable_inventory => 1,
                                   disable_select => 1,
                                 },
        'upbytes_threshold'   => { label => 'Upload threshold',
                                   type  => 'text',
                                   disable_inventory => 1,
                                   disable_select => 1,
                                   'format' => \&FS::UI::bytecount::display_bytecount,
                                   'parse' => \&FS::UI::bytecount::parse_bytecount,
                                 },
        'downbytes_threshold' => { label => 'Download threshold',
                                   type  => 'text',
                                   disable_inventory => 1,
                                   disable_select => 1,
                                   'format' => \&FS::UI::bytecount::display_bytecount,
                                   'parse' => \&FS::UI::bytecount::parse_bytecount,
                                 },
        'totalbytes_threshold'=> { label => 'Total up and download threshold',
                                   type  => 'text',
                                   disable_inventory => 1,
                                   disable_select => 1,
                                   'format' => \&FS::UI::bytecount::display_bytecount,
                                   'parse' => \&FS::UI::bytecount::parse_bytecount,
                                 },
    },
  };
}

sub table { 'svc_acct'; }

sub _fieldhandlers {
  {
    #false laziness with edit/svc_acct.cgi
    'usergroup' => sub { 
                         my( $self, $groups ) = @_;
                         if ( ref($groups) eq 'ARRAY' ) {
                           $groups;
                         } elsif ( length($groups) ) {
                           [ split(/\s*,\s*/, $groups) ];
                         } else {
                           [];
                         }
                       },
  };
}

=item search_sql STRING

Class method which returns an SQL fragment to search for the given string.

=cut

sub search_sql {
  my( $class, $string ) = @_;
  if ( $string =~ /^([^@]+)@([^@]+)$/ ) {
    my( $username, $domain ) = ( $1, $2 );
    my $q_username = dbh->quote($username);
    my @svc_domain = qsearch('svc_domain', { 'domain' => $domain } );
    if ( @svc_domain ) {
      "svc_acct.username = $q_username AND ( ".
        join( ' OR ', map { "svc_acct.domsvc = ". $_->svcnum; } @svc_domain ).
      " )";
    } else {
      '1 = 0'; #false
    }
  } elsif ( $string =~ /^(\d{1,3}\.){3}\d{1,3}$/ ) {
    ' ( '.
      $class->search_sql_field('slipip',   $string ).
    ' OR '.
      $class->search_sql_field('username', $string ).
    ' ) ';
  } else {
    $class->search_sql_field('username', $string);
  }
}

=item label [ END_TIMESTAMP [ START_TIMESTAMP ] ]

Returns the "username@domain" string for this account.

END_TIMESTAMP and START_TIMESTAMP can optionally be passed when dealing with
history records.

=cut

sub label {
  my $self = shift;
  $self->email(@_);
}

=cut

=item insert [ , OPTION => VALUE ... ]

Adds this account to the database.  If there is an error, returns the error,
otherwise returns false.

The additional fields pkgnum and svcpart (see L<FS::cust_svc>) should be 
defined.  An FS::cust_svc record will be created and inserted.

The additional field I<usergroup> can optionally be defined; if so it should
contain an arrayref of group names.  See L<FS::radius_usergroup>.

The additional field I<child_objects> can optionally be defined; if so it
should contain an arrayref of FS::tablename objects.  They will have their
svcnum fields set and will be inserted after this record, but before any
exports are run.  Each element of the array can also optionally be a
two-element array reference containing the child object and the name of an
alternate field to be filled in with the newly-inserted svcnum, for example
C<[ $svc_forward, 'srcsvc' ]>

Currently available options are: I<depend_jobnum>

If I<depend_jobnum> is set (to a scalar jobnum or an array reference of
jobnums), all provisioning jobs will have a dependancy on the supplied
jobnum(s) (they will not run until the specific job(s) complete(s)).

(TODOC: L<FS::queue> and L<freeside-queued>)

(TODOC: new exports!)

=cut

sub insert {
  my $self = shift;
  my %options = @_;

  if ( $DEBUG ) {
    warn "[$me] insert called on $self: ". Dumper($self).
         "\nwith options: ". Dumper(%options);
  }

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $error = $self->check;
  return $error if $error;

  if ( $self->svcnum && qsearchs('cust_svc',{'svcnum'=>$self->svcnum}) ) {
    my $cust_svc = qsearchs('cust_svc',{'svcnum'=>$self->svcnum});
    unless ( $cust_svc ) {
      $dbh->rollback if $oldAutoCommit;
      return "no cust_svc record found for svcnum ". $self->svcnum;
    }
    $self->pkgnum($cust_svc->pkgnum);
    $self->svcpart($cust_svc->svcpart);
  }

  $error = $self->_check_duplicate;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  my @jobnums;
  $error = $self->SUPER::insert(
    'jobnums'       => \@jobnums,
    'child_objects' => $self->child_objects,
    %options,
  );
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  if ( $self->usergroup ) {
    foreach my $groupname ( @{$self->usergroup} ) {
      my $radius_usergroup = new FS::radius_usergroup ( {
        svcnum    => $self->svcnum,
        groupname => $groupname,
      } );
      my $error = $radius_usergroup->insert;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return $error;
      }
    }
  }

  unless ( $skip_fuzzyfiles ) {
    $error = $self->queue_fuzzyfiles_update;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "updating fuzzy search cache: $error";
    }
  }

  my $cust_pkg = $self->cust_svc->cust_pkg;

  if ( $cust_pkg ) {
    my $cust_main = $cust_pkg->cust_main;

    if (   $conf->exists('emailinvoiceautoalways')
        || $conf->exists('emailinvoiceauto')
        && ! $cust_main->invoicing_list_emailonly
       ) {
      my @invoicing_list = $cust_main->invoicing_list;
      push @invoicing_list, $self->email;
      $cust_main->invoicing_list(\@invoicing_list);
    }

    #welcome email
    my $to = '';
    if ( $welcome_template && $cust_pkg ) {
      my $to = join(', ', grep { $_ !~ /^(POST|FAX)$/ } $cust_main->invoicing_list );
      if ( $to ) {

        my %hash = (
                     'custnum'  => $self->custnum,
                     'username' => $self->username,
                     'password' => $self->_password,
                     'first'    => $cust_main->first,
                     'last'     => $cust_main->getfield('last'),
                     'pkg'      => $cust_pkg->part_pkg->pkg,
                   );
        my $wqueue = new FS::queue {
          'svcnum' => $self->svcnum,
          'job'    => 'FS::svc_acct::send_email'
        };
        my $error = $wqueue->insert(
          'to'       => $to,
          'from'     => $welcome_from,
          'subject'  => $welcome_subject_template->fill_in( HASH => \%hash, ),
          'mimetype' => $welcome_mimetype,
          'body'     => $welcome_template->fill_in( HASH => \%hash, ),
        );
        if ( $error ) {
          $dbh->rollback if $oldAutoCommit;
          return "error queuing welcome email: $error";
        }

        if ( $options{'depend_jobnum'} ) {
          warn "$me depend_jobnum found; adding to welcome email dependancies"
            if $DEBUG;
          if ( ref($options{'depend_jobnum'}) ) {
            warn "$me adding jobs ". join(', ', @{$options{'depend_jobnum'}} ).
                 "to welcome email dependancies"
              if $DEBUG;
            push @jobnums, @{ $options{'depend_jobnum'} };
          } else {
            warn "$me adding job $options{'depend_jobnum'} ".
                 "to welcome email dependancies"
              if $DEBUG;
            push @jobnums, $options{'depend_jobnum'};
          }
        }

        foreach my $jobnum ( @jobnums ) {
          my $error = $wqueue->depend_insert($jobnum);
          if ( $error ) {
            $dbh->rollback if $oldAutoCommit;
            return "error queuing welcome email job dependancy: $error";
          }
        }

      }

    }

  } # if ( $cust_pkg )

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  ''; #no error
}

=item delete

Deletes this account from the database.  If there is an error, returns the
error, otherwise returns false.

The corresponding FS::cust_svc record will be deleted as well.

(TODOC: new exports!)

=cut

sub delete {
  my $self = shift;

  return "can't delete system account" if $self->_check_system;

  return "Can't delete an account which is a (svc_forward) source!"
    if qsearch( 'svc_forward', { 'srcsvc' => $self->svcnum } );

  return "Can't delete an account which is a (svc_forward) destination!"
    if qsearch( 'svc_forward', { 'dstsvc' => $self->svcnum } );

  return "Can't delete an account with (svc_www) web service!"
    if qsearch( 'svc_www', { 'usersvc' => $self->svcnum } );

  # what about records in session ? (they should refer to history table)

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  foreach my $cust_main_invoice (
    qsearch( 'cust_main_invoice', { 'dest' => $self->svcnum } )
  ) {
    unless ( defined($cust_main_invoice) ) {
      warn "WARNING: something's wrong with qsearch";
      next;
    }
    my %hash = $cust_main_invoice->hash;
    $hash{'dest'} = $self->email;
    my $new = new FS::cust_main_invoice \%hash;
    my $error = $new->replace($cust_main_invoice);
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  foreach my $svc_domain (
    qsearch( 'svc_domain', { 'catchall' => $self->svcnum } )
  ) {
    my %hash = new FS::svc_domain->hash;
    $hash{'catchall'} = '';
    my $new = new FS::svc_domain \%hash;
    my $error = $new->replace($svc_domain);
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  my $error = $self->SUPER::delete;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  foreach my $radius_usergroup (
    qsearch('radius_usergroup', { 'svcnum' => $self->svcnum } )
  ) {
    my $error = $radius_usergroup->delete;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  '';
}

=item replace OLD_RECORD

Replaces OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

The additional field I<usergroup> can optionally be defined; if so it should
contain an arrayref of group names.  See L<FS::radius_usergroup>.


=cut

sub replace {
  my ( $new, $old ) = ( shift, shift );
  my $error;
  warn "$me replacing $old with $new\n" if $DEBUG;

  # We absolutely have to have an old vs. new record to make this work.
  if (!defined($old)) {
    $old = qsearchs( 'svc_acct', { 'svcnum' => $new->svcnum } );
  }

  return "can't modify system account" if $old->_check_system;

  {
    #no warnings 'numeric';  #alas, a 5.006-ism
    local($^W) = 0;

    foreach my $xid (qw( uid gid )) {

      return "Can't change $xid!"
        if ! $conf->exists("svc_acct-edit_$xid")
           && $old->$xid() != $new->$xid()
           && $new->cust_svc->part_svc->part_svc_column($xid)->columnflag ne 'F'
    }

  }

  #change homdir when we change username
  $new->setfield('dir', '') if $old->username ne $new->username;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  # redundant, but so $new->usergroup gets set
  $error = $new->check;
  return $error if $error;

  $old->usergroup( [ $old->radius_groups ] );
  if ( $DEBUG ) {
    warn $old->email. " old groups: ". join(' ',@{$old->usergroup}). "\n";
    warn $new->email. "new groups: ". join(' ',@{$new->usergroup}). "\n";
  }
  if ( $new->usergroup ) {
    #(sorta) false laziness with FS::part_export::sqlradius::_export_replace
    my @newgroups = @{$new->usergroup};
    foreach my $oldgroup ( @{$old->usergroup} ) {
      if ( grep { $oldgroup eq $_ } @newgroups ) {
        @newgroups = grep { $oldgroup ne $_ } @newgroups;
        next;
      }
      my $radius_usergroup = qsearchs('radius_usergroup', {
        svcnum    => $old->svcnum,
        groupname => $oldgroup,
      } );
      my $error = $radius_usergroup->delete;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "error deleting radius_usergroup $oldgroup: $error";
      }
    }

    foreach my $newgroup ( @newgroups ) {
      my $radius_usergroup = new FS::radius_usergroup ( {
        svcnum    => $new->svcnum,
        groupname => $newgroup,
      } );
      my $error = $radius_usergroup->insert;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "error adding radius_usergroup $newgroup: $error";
      }
    }

  }

  if ( $old->username ne $new->username || $old->domsvc != $new->domsvc ) {
    $new->svcpart( $new->cust_svc->svcpart ) unless $new->svcpart;
    $error = $new->_check_duplicate;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  $error = $new->SUPER::replace($old);
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error if $error;
  }

  if ( $new->username ne $old->username && ! $skip_fuzzyfiles ) {
    $error = $new->queue_fuzzyfiles_update;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "updating fuzzy search cache: $error";
    }
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  ''; #no error
}

=item queue_fuzzyfiles_update

Used by insert & replace to update the fuzzy search cache

=cut

sub queue_fuzzyfiles_update {
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

  my $queue = new FS::queue {
    'svcnum' => $self->svcnum,
    'job'    => 'FS::svc_acct::append_fuzzyfiles'
  };
  my $error = $queue->insert($self->username);
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return "queueing job (transaction rolled back): $error";
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  '';

}


=item suspend

Suspends this account by calling export-specific suspend hooks.  If there is
an error, returns the error, otherwise returns false.

Called by the suspend method of FS::cust_pkg (see L<FS::cust_pkg>).

=cut

sub suspend {
  my $self = shift;
  return "can't suspend system account" if $self->_check_system;
  $self->SUPER::suspend;
}

=item unsuspend

Unsuspends this account by by calling export-specific suspend hooks.  If there
is an error, returns the error, otherwise returns false.

Called by the unsuspend method of FS::cust_pkg (see L<FS::cust_pkg>).

=cut

sub unsuspend {
  my $self = shift;
  my %hash = $self->hash;
  if ( $hash{_password} =~ /^\*SUSPENDED\* (.*)$/ ) {
    $hash{_password} = $1;
    my $new = new FS::svc_acct ( \%hash );
    my $error = $new->replace($self);
    return $error if $error;
  }

  $self->SUPER::unsuspend;
}

=item cancel

Called by the cancel method of FS::cust_pkg (see L<FS::cust_pkg>).

If the B<auto_unset_catchall> configuration option is set, this method will
automatically remove any references to the canceled service in the catchall
field of svc_domain.  This allows packages that contain both a svc_domain and
its catchall svc_acct to be canceled in one step.

=cut

sub cancel {
  # Only one thing to do at this level
  my $self = shift;
  foreach my $svc_domain (
      qsearch( 'svc_domain', { catchall => $self->svcnum } ) ) {
    if($conf->exists('auto_unset_catchall')) {
      my %hash = $svc_domain->hash;
      $hash{catchall} = '';
      my $new = new FS::svc_domain ( \%hash );
      my $error = $new->replace($svc_domain);
      return $error if $error;
    } else {
      return "cannot unprovision svc_acct #".$self->svcnum.
	  " while assigned as catchall for svc_domain #".$svc_domain->svcnum;
    }
  }

  $self->SUPER::cancel;
}


=item check

Checks all fields to make sure this is a valid service.  If there is an error,
returns the error, otherwise returns false.  Called by the insert and replace
methods.

Sets any fixed values; see L<FS::part_svc>.

=cut

sub check {
  my $self = shift;

  my($recref) = $self->hashref;

  my $x = $self->setfixed( $self->_fieldhandlers );
  return $x unless ref($x);
  my $part_svc = $x;

  if ( $part_svc->part_svc_column('usergroup')->columnflag eq "F" ) {
    $self->usergroup(
      [ split(',', $part_svc->part_svc_column('usergroup')->columnvalue) ] );
  }

  my $error = $self->ut_numbern('svcnum')
              #|| $self->ut_number('domsvc')
              || $self->ut_foreign_key('domsvc', 'svc_domain', 'svcnum' )
              || $self->ut_textn('sec_phrase')
              || $self->ut_snumbern('seconds')
              || $self->ut_snumbern('upbytes')
              || $self->ut_snumbern('downbytes')
              || $self->ut_snumbern('totalbytes')
  ;
  return $error if $error;

  my $ulen = $usernamemax || $self->dbdef_table->column('username')->length;
  if ( $username_uppercase ) {
    $recref->{username} =~ /^([a-z0-9_\-\.\&\%]{$usernamemin,$ulen})$/i
      or return gettext('illegal_username'). " ($usernamemin-$ulen): ". $recref->{username};
    $recref->{username} = $1;
  } else {
    $recref->{username} =~ /^([a-z0-9_\-\.\&\%]{$usernamemin,$ulen})$/
      or return gettext('illegal_username'). " ($usernamemin-$ulen): ". $recref->{username};
    $recref->{username} = $1;
  }

  if ( $username_letterfirst ) {
    $recref->{username} =~ /^[a-z]/ or return gettext('illegal_username');
  } elsif ( $username_letter ) {
    $recref->{username} =~ /[a-z]/ or return gettext('illegal_username');
  }
  if ( $username_noperiod ) {
    $recref->{username} =~ /\./ and return gettext('illegal_username');
  }
  if ( $username_nounderscore ) {
    $recref->{username} =~ /_/ and return gettext('illegal_username');
  }
  if ( $username_nodash ) {
    $recref->{username} =~ /\-/ and return gettext('illegal_username');
  }
  unless ( $username_ampersand ) {
    $recref->{username} =~ /\&/ and return gettext('illegal_username');
  }
  if ( $password_noampersand ) {
    $recref->{_password} =~ /\&/ and return gettext('illegal_password');
  }
  if ( $password_noexclamation ) {
    $recref->{_password} =~ /\!/ and return gettext('illegal_password');
  }
  unless ( $username_percent ) {
    $recref->{username} =~ /\%/ and return gettext('illegal_username');
  }

  $recref->{popnum} =~ /^(\d*)$/ or return "Illegal popnum: ".$recref->{popnum};
  $recref->{popnum} = $1;
  return "Unknown popnum" unless
    ! $recref->{popnum} ||
    qsearchs('svc_acct_pop',{'popnum'=> $recref->{popnum} } );

  unless ( $part_svc->part_svc_column('uid')->columnflag eq 'F' ) {

    $recref->{uid} =~ /^(\d*)$/ or return "Illegal uid";
    $recref->{uid} = $1 eq '' ? $self->unique('uid') : $1;

    $recref->{gid} =~ /^(\d*)$/ or return "Illegal gid";
    $recref->{gid} = $1 eq '' ? $recref->{uid} : $1;
    #not all systems use gid=uid
    #you can set a fixed gid in part_svc

    return "Only root can have uid 0"
      if $recref->{uid} == 0
         && $recref->{username} !~ /^(root|toor|smtp)$/;

    unless ( $recref->{username} eq 'sync' ) {
      if ( grep $_ eq $recref->{shell}, @shells ) {
        $recref->{shell} = (grep $_ eq $recref->{shell}, @shells)[0];
      } else {
        return "Illegal shell \`". $self->shell. "\'; ".
               $conf->dir. "/shells contains: @shells";
      }
    } else {
      $recref->{shell} = '/bin/sync';
    }

  } else {
    $recref->{gid} ne '' ? 
      return "Can't have gid without uid" : ( $recref->{gid}='' );
    #$recref->{dir} ne '' ? 
    #  return "Can't have directory without uid" : ( $recref->{dir}='' );
    $recref->{shell} ne '' ? 
      return "Can't have shell without uid" : ( $recref->{shell}='' );
  }

  unless ( $part_svc->part_svc_column('dir')->columnflag eq 'F' ) {

    $recref->{dir} =~ /^([\/\w\-\.\&]*)$/
      or return "Illegal directory: ". $recref->{dir};
    $recref->{dir} = $1;
    return "Illegal directory"
      if $recref->{dir} =~ /(^|\/)\.+(\/|$)/; #no .. component
    return "Illegal directory"
      if $recref->{dir} =~ /\&/ && ! $username_ampersand;
    unless ( $recref->{dir} ) {
      $recref->{dir} = $dir_prefix . '/';
      if ( $dirhash > 0 ) {
        for my $h ( 1 .. $dirhash ) {
          $recref->{dir} .= substr($recref->{username}, $h-1, 1). '/';
        }
      } elsif ( $dirhash < 0 ) {
        for my $h ( reverse $dirhash .. -1 ) {
          $recref->{dir} .= substr($recref->{username}, $h, 1). '/';
        }
      }
      $recref->{dir} .= $recref->{username};
    ;
    }

  }

  #  $error = $self->ut_textn('finger');
  #  return $error if $error;
  if ( $self->getfield('finger') eq '' ) {
    my $cust_pkg = $self->svcnum
      ? $self->cust_svc->cust_pkg
      : qsearchs('cust_pkg', { 'pkgnum' => $self->getfield('pkgnum') } );
    if ( $cust_pkg ) {
      my $cust_main = $cust_pkg->cust_main;
      $self->setfield('finger', $cust_main->first.' '.$cust_main->get('last') );
    }
  }
  $self->getfield('finger') =~
    /^([\w \t\!\@\#\$\%\&\(\)\-\+\;\'\"\,\.\?\/\*\<\>]*)$/
      or return "Illegal finger: ". $self->getfield('finger');
  $self->setfield('finger', $1);

  $recref->{quota} =~ /^(\w*)$/ or return "Illegal quota";
  $recref->{quota} = $1;

  unless ( $part_svc->part_svc_column('slipip')->columnflag eq 'F' ) {
    if ( $recref->{slipip} eq '' ) {
      $recref->{slipip} = '';
    } elsif ( $recref->{slipip} eq '0e0' ) {
      $recref->{slipip} = '0e0';
    } else {
      $recref->{slipip} =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/
        or return "Illegal slipip: ". $self->slipip;
      $recref->{slipip} = $1;
    }

  }

  #arbitrary RADIUS stuff; allow ut_textn for now
  foreach ( grep /^radius_/, fields('svc_acct') ) {
    $self->ut_textn($_);
  }

  #generate a password if it is blank
  $recref->{_password} = join('',map($pw_set[ int(rand $#pw_set) ], (0..7) ) )
    unless ( $recref->{_password} );

  #if ( $recref->{_password} =~ /^((\*SUSPENDED\* )?)([^\t\n]{4,16})$/ ) {
  if ( $recref->{_password} =~ /^((\*SUSPENDED\* |!!?)?)([^\t\n]{$passwordmin,$passwordmax})$/ ) {
    $recref->{_password} = $1.$3;
    #uncomment this to encrypt password immediately upon entry, or run
    #bin/crypt_pw in cron to give new users a window during which their
    #password is available to techs, for faxing, etc.  (also be aware of 
    #radius issues!)
    #$recref->{password} = $1.
    #  crypt($3,$saltset[int(rand(64))].$saltset[int(rand(64))]
    #;
  } elsif ( $recref->{_password} =~ /^((\*SUSPENDED\* |!!?)?)([\w\.\/\$\;\+]{13,64})$/ ) {
    $recref->{_password} = $1.$3;
  } elsif ( $recref->{_password} eq '*' ) {
    $recref->{_password} = '*';
  } elsif ( $recref->{_password} eq '!' ) {
    $recref->{_password} = '!';
  } elsif ( $recref->{_password} eq '!!' ) {
    $recref->{_password} = '!!';
  } else {
    #return "Illegal password";
    return gettext('illegal_password'). " $passwordmin-$passwordmax ".
           FS::Msgcat::_gettext('illegal_password_characters').
           ": ". $recref->{_password};
  }

  $self->SUPER::check;
}

=item _check_system

Internal function to check the username against the list of system usernames
from the I<system_usernames> configuration value.  Returns true if the username
is listed on the system username list.

=cut

sub _check_system {
  my $self = shift;
  scalar( grep { $self->username eq $_ || $self->email eq $_ }
               $conf->config('system_usernames')
        );
}

=item _check_duplicate

Internal function to check for duplicates usernames, username@domain pairs and
uids.

If the I<global_unique-username> configuration value is set to B<username> or
B<username@domain>, enforces global username or username@domain uniqueness.

In all cases, check for duplicate uids and usernames or username@domain pairs
per export and with identical I<svcpart> values.

=cut

sub _check_duplicate {
  my $self = shift;

  my $global_unique = $conf->config('global_unique-username') || 'none';
  return '' if $global_unique eq 'disabled';

  warn "$me locking svc_acct table for duplicate search" if $DEBUG;
  if ( driver_name =~ /^Pg/i ) {
    dbh->do("LOCK TABLE svc_acct IN SHARE ROW EXCLUSIVE MODE")
      or die dbh->errstr;
  } elsif ( driver_name =~ /^mysql/i ) {
    dbh->do("SELECT * FROM duplicate_lock
               WHERE lockname = 'svc_acct'
	       FOR UPDATE"
	   ) or die dbh->errstr;
  } else {
    die "unknown database ". driver_name.
        "; don't know how to lock for duplicate search";
  }
  warn "$me acquired svc_acct table lock for duplicate search" if $DEBUG;

  my $part_svc = qsearchs('part_svc', { 'svcpart' => $self->svcpart } );
  unless ( $part_svc ) {
    return 'unknown svcpart '. $self->svcpart;
  }

  my @dup_user = grep { !$self->svcnum || $_->svcnum != $self->svcnum }
                 qsearch( 'svc_acct', { 'username' => $self->username } );
  return gettext('username_in_use')
    if $global_unique eq 'username' && @dup_user;

  my @dup_userdomain = grep { !$self->svcnum || $_->svcnum != $self->svcnum }
                       qsearch( 'svc_acct', { 'username' => $self->username,
                                              'domsvc'   => $self->domsvc } );
  return gettext('username_in_use')
    if $global_unique eq 'username@domain' && @dup_userdomain;

  my @dup_uid;
  if ( $part_svc->part_svc_column('uid')->columnflag ne 'F'
       && $self->username !~ /^(toor|(hyla)?fax)$/          ) {
    @dup_uid = grep { !$self->svcnum || $_->svcnum != $self->svcnum }
               qsearch( 'svc_acct', { 'uid' => $self->uid } );
  } else {
    @dup_uid = ();
  }

  if ( @dup_user || @dup_userdomain || @dup_uid ) {
    my $exports = FS::part_export::export_info('svc_acct');
    my %conflict_user_svcpart;
    my %conflict_userdomain_svcpart = ( $self->svcpart => 'SELF', );

    foreach my $part_export ( $part_svc->part_export ) {

      #this will catch to the same exact export
      my @svcparts = map { $_->svcpart } $part_export->export_svc;

      #this will catch to exports w/same exporthost+type ???
      #my @other_part_export = qsearch('part_export', {
      #  'machine'    => $part_export->machine,
      #  'exporttype' => $part_export->exporttype,
      #} );
      #foreach my $other_part_export ( @other_part_export ) {
      #  push @svcparts, map { $_->svcpart }
      #    qsearch('export_svc', { 'exportnum' => $part_export->exportnum });
      #}

      #my $nodomain = $exports->{$part_export->exporttype}{'nodomain'};
      #silly kludge to avoid uninitialized value errors
      my $nodomain = exists( $exports->{$part_export->exporttype}{'nodomain'} )
                     ? $exports->{$part_export->exporttype}{'nodomain'}
                     : '';
      if ( $nodomain =~ /^Y/i ) {
        $conflict_user_svcpart{$_} = $part_export->exportnum
          foreach @svcparts;
      } else {
        $conflict_userdomain_svcpart{$_} = $part_export->exportnum
          foreach @svcparts;
      }
    }

    foreach my $dup_user ( @dup_user ) {
      my $dup_svcpart = $dup_user->cust_svc->svcpart;
      if ( exists($conflict_user_svcpart{$dup_svcpart}) ) {
        return "duplicate username: conflicts with svcnum ". $dup_user->svcnum.
               " via exportnum ". $conflict_user_svcpart{$dup_svcpart};
      }
    }

    foreach my $dup_userdomain ( @dup_userdomain ) {
      my $dup_svcpart = $dup_userdomain->cust_svc->svcpart;
      if ( exists($conflict_userdomain_svcpart{$dup_svcpart}) ) {
        return "duplicate username\@domain: conflicts with svcnum ".
               $dup_userdomain->svcnum. " via exportnum ".
               $conflict_userdomain_svcpart{$dup_svcpart};
      }
    }

    foreach my $dup_uid ( @dup_uid ) {
      my $dup_svcpart = $dup_uid->cust_svc->svcpart;
      if ( exists($conflict_user_svcpart{$dup_svcpart})
           || exists($conflict_userdomain_svcpart{$dup_svcpart}) ) {
        return "duplicate uid: conflicts with svcnum ". $dup_uid->svcnum.
               " via exportnum ". $conflict_user_svcpart{$dup_svcpart}
                                 || $conflict_userdomain_svcpart{$dup_svcpart};
      }
    }

  }

  return '';

}

=item radius

Depriciated, use radius_reply instead.

=cut

sub radius {
  carp "FS::svc_acct::radius depriciated, use radius_reply";
  $_[0]->radius_reply;
}

=item radius_reply

Returns key/value pairs, suitable for assigning to a hash, for any RADIUS
reply attributes of this record.

Note that this is now the preferred method for reading RADIUS attributes - 
accessing the columns directly is discouraged, as the column names are
expected to change in the future.

=cut

sub radius_reply { 
  my $self = shift;

  return %{ $self->{'radius_reply'} }
    if exists $self->{'radius_reply'};

  my %reply =
    map {
      /^(radius_(.*))$/;
      my($column, $attrib) = ($1, $2);
      #$attrib =~ s/_/\-/g;
      ( $FS::raddb::attrib{lc($attrib)}, $self->getfield($column) );
    } grep { /^radius_/ && $self->getfield($_) } fields( $self->table );

  if ( $self->slipip && $self->slipip ne '0e0' ) {
    $reply{$radius_ip} = $self->slipip;
  }

  if ( $self->seconds !~ /^$/ ) {
    $reply{'Session-Timeout'} = $self->seconds;
  }

  %reply;
}

=item radius_check

Returns key/value pairs, suitable for assigning to a hash, for any RADIUS
check attributes of this record.

Note that this is now the preferred method for reading RADIUS attributes - 
accessing the columns directly is discouraged, as the column names are
expected to change in the future.

=cut

sub radius_check {
  my $self = shift;

  return %{ $self->{'radius_check'} }
    if exists $self->{'radius_check'};

  my %check = 
    map {
      /^(rc_(.*))$/;
      my($column, $attrib) = ($1, $2);
      #$attrib =~ s/_/\-/g;
      ( $FS::raddb::attrib{lc($attrib)}, $self->getfield($column) );
    } grep { /^rc_/ && $self->getfield($_) } fields( $self->table );

  my $password = $self->_password;
  my $pw_attrib = length($password) <= 12 ? $radius_password : 'Crypt-Password';  $check{$pw_attrib} = $password;

  my $cust_svc = $self->cust_svc;
  die "FATAL: no cust_svc record for svc_acct.svcnum ". $self->svcnum. "\n"
    unless $cust_svc;
  my $cust_pkg = $cust_svc->cust_pkg;
  if ( $cust_pkg && $cust_pkg->part_pkg->is_prepaid && $cust_pkg->bill ) {
    $check{'Expiration'} = time2str('%B %e %Y %T', $cust_pkg->bill ); #http://lists.cistron.nl/pipermail/freeradius-users/2005-January/040184.html
  }

  %check;

}

=item snapshot

This method instructs the object to "snapshot" or freeze RADIUS check and
reply attributes to the current values.

=cut

#bah, my english is too broken this morning
#Of note is the "Expiration" attribute, which, for accounts in prepaid packages, is typically defined on-the-fly as the associated packages cust_pkg.bill.  (This is used by
#the FS::cust_pkg's replace method to trigger the correct export updates when
#package dates change)

sub snapshot {
  my $self = shift;

  $self->{$_} = { $self->$_() }
    foreach qw( radius_reply radius_check );

}

=item forget_snapshot

This methos instructs the object to forget any previously snapshotted
RADIUS check and reply attributes.

=cut

sub forget_snapshot {
  my $self = shift;

  delete $self->{$_}
    foreach qw( radius_reply radius_check );

}

=item domain [ END_TIMESTAMP [ START_TIMESTAMP ] ]

Returns the domain associated with this account.

END_TIMESTAMP and START_TIMESTAMP can optionally be passed when dealing with
history records.

=cut

sub domain {
  my $self = shift;
  die "svc_acct.domsvc is null for svcnum ". $self->svcnum unless $self->domsvc;
  my $svc_domain = $self->svc_domain(@_)
    or die "no svc_domain.svcnum for svc_acct.domsvc ". $self->domsvc;
  $svc_domain->domain;
}

=item svc_domain

Returns the FS::svc_domain record for this account's domain (see
L<FS::svc_domain>).

=cut

# FS::h_svc_acct has a history-aware svc_domain override

sub svc_domain {
  my $self = shift;
  $self->{'_domsvc'}
    ? $self->{'_domsvc'}
    : qsearchs( 'svc_domain', { 'svcnum' => $self->domsvc } );
}

=item cust_svc

Returns the FS::cust_svc record for this account (see L<FS::cust_svc>).

=cut

#inherited from svc_Common

=item email [ END_TIMESTAMP [ START_TIMESTAMP ] ]

Returns an email address associated with the account.

END_TIMESTAMP and START_TIMESTAMP can optionally be passed when dealing with
history records.

=cut

sub email {
  my $self = shift;
  $self->username. '@'. $self->domain(@_);
}

=item acct_snarf

Returns an array of FS::acct_snarf records associated with the account.
If the acct_snarf table does not exist or there are no associated records,
an empty list is returned

=cut

sub acct_snarf {
  my $self = shift;
  return () unless dbdef->table('acct_snarf');
  eval "use FS::acct_snarf;";
  die $@ if $@;
  qsearch('acct_snarf', { 'svcnum' => $self->svcnum } );
}

=item decrement_upbytes OCTETS

Decrements the I<upbytes> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub decrement_upbytes {
  shift->_op_usage('-', 'upbytes', @_);
}

=item increment_upbytes OCTETS

Increments the I<upbytes> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub increment_upbytes {
  shift->_op_usage('+', 'upbytes', @_);
}

=item decrement_downbytes OCTETS

Decrements the I<downbytes> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub decrement_downbytes {
  shift->_op_usage('-', 'downbytes', @_);
}

=item increment_downbytes OCTETS

Increments the I<downbytes> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub increment_downbytes {
  shift->_op_usage('+', 'downbytes', @_);
}

=item decrement_totalbytes OCTETS

Decrements the I<totalbytes> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub decrement_totalbytes {
  shift->_op_usage('-', 'totalbytes', @_);
}

=item increment_totalbytes OCTETS

Increments the I<totalbytes> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub increment_totalbytes {
  shift->_op_usage('+', 'totalbytes', @_);
}

=item decrement_seconds SECONDS

Decrements the I<seconds> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub decrement_seconds {
  shift->_op_usage('-', 'seconds', @_);
}

=item increment_seconds SECONDS

Increments the I<seconds> field of this record by the given amount.  If there
is an error, returns the error, otherwise returns false.

=cut

sub increment_seconds {
  shift->_op_usage('+', 'seconds', @_);
}


my %op2action = (
  '-' => 'suspend',
  '+' => 'unsuspend',
);
my %op2condition = (
  '-' => sub { my($self, $column, $amount) = @_;
               $self->$column - $amount <= 0;
             },
  '+' => sub { my($self, $column, $amount) = @_;
               $self->$column + $amount > 0;
             },
);
my %op2warncondition = (
  '-' => sub { my($self, $column, $amount) = @_;
               my $threshold = $column . '_threshold';
               $self->$column - $amount <= $self->$threshold + 0;
             },
  '+' => sub { my($self, $column, $amount) = @_;
               $self->$column + $amount > 0;
             },
);

sub _op_usage {
  my( $self, $op, $column, $amount ) = @_;

  warn "$me _op_usage called for $column on svcnum ". $self->svcnum.
       ' ('. $self->email. "): $op $amount\n"
    if $DEBUG;

  return '' unless $amount;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $sql = "UPDATE svc_acct SET $column = ".
            " CASE WHEN $column IS NULL THEN 0 ELSE $column END ". #$column||0
            " $op ? WHERE svcnum = ?";
  warn "$me $sql\n"
    if $DEBUG;

  my $sth = $dbh->prepare( $sql )
    or die "Error preparing $sql: ". $dbh->errstr;
  my $rv = $sth->execute($amount, $self->svcnum);
  die "Error executing $sql: ". $sth->errstr
    unless defined($rv);
  die "Can't update $column for svcnum". $self->svcnum
    if $rv == 0;

  my $action = $op2action{$op};

  if ( &{$op2condition{$op}}($self, $column, $amount) &&
        ( $action eq 'suspend'   && !$self->overlimit 
       || $action eq 'unsuspend' &&  $self->overlimit ) 
     ) {
    foreach my $part_export ( $self->cust_svc->part_svc->part_export ) {
      if ($part_export->option('overlimit_groups')) {
        my ($new,$old);
        my $other = new FS::svc_acct $self->hashref;
        my $groups = &{ $self->_fieldhandlers->{'usergroup'} }
                       ($self, $part_export->option('overlimit_groups'));
        $other->usergroup( $groups );
        if ($action eq 'suspend'){
          $new = $other; $old = $self;
        }else{
          $new = $self; $old = $other;
        }
        my $error = $part_export->export_replace($new, $old);
        $error ||= $self->overlimit($action);
        if ( $error ) {
          $dbh->rollback if $oldAutoCommit;
          return "Error replacing radius groups in export, ${op}: $error";
        }
      }
    }
  }

  if ( $conf->exists("svc_acct-usage_$action")
       && &{$op2condition{$op}}($self, $column, $amount)    ) {
    #my $error = $self->$action();
    my $error = $self->cust_svc->cust_pkg->$action();
    # $error ||= $self->overlimit($action);
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "Error ${action}ing: $error";
    }
  }

  if ($warning_template && &{$op2warncondition{$op}}($self, $column, $amount)) {
    my $wqueue = new FS::queue {
      'svcnum' => $self->svcnum,
      'job'    => 'FS::svc_acct::reached_threshold',
    };

    my $to = '';
    if ($op eq '-'){
      $to = $warning_cc if &{$op2condition{$op}}($self, $column, $amount);
    }

    # x_threshold race
    my $error = $wqueue->insert(
      'svcnum' => $self->svcnum,
      'op'     => $op,
      'column' => $column,
      'to'     => $to,
    );
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "Error queuing threshold activity: $error";
    }
  }

  warn "$me update successful; committing\n"
    if $DEBUG;
  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  '';

}

sub set_usage {
  my( $self, $valueref ) = @_;

  warn "$me set_usage called for svcnum ". $self->svcnum.
       ' ('. $self->email. "): ".
       join(', ', map { "$_ => " . $valueref->{$_}} keys %$valueref) . "\n"
    if $DEBUG;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  local $FS::svc_Common::noexport_hack = 1;
  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $reset = 0;
  my %handyhash = ();
  foreach my $field (keys %$valueref){
    $reset = 1 if $valueref->{$field};
    $self->setfield($field, $valueref->{$field});
    $self->setfield( $field.'_threshold',
                     int($self->getfield($field)
                         * ( $conf->exists('svc_acct-usage_threshold') 
                             ? 1 - $conf->config('svc_acct-usage_threshold')/100
                             : 0.20
                           )
                       )
                     );
    $handyhash{$field} = $self->getfield($field);
    $handyhash{$field.'_threshold'} = $self->getfield($field.'_threshold');
  }
  #my $error = $self->replace;   #NO! we avoid the call to ->check for
  #die $error if $error;         #services not explicity changed via the UI

  my $sql = "UPDATE svc_acct SET " .
    join (',', map { "$_ =  ?" } (keys %handyhash) ).
    " WHERE svcnum = ?";

  warn "$me $sql\n"
    if $DEBUG;

  if (scalar(keys %handyhash)) {
    my $sth = $dbh->prepare( $sql )
      or die "Error preparing $sql: ". $dbh->errstr;
    my $rv = $sth->execute((values %handyhash), $self->svcnum);
    die "Error executing $sql: ". $sth->errstr
      unless defined($rv);
    die "Can't update usage for svcnum ". $self->svcnum
      if $rv == 0;
  }

  if ( $reset ) {
    my $error;

    if ($self->overlimit) {
      $error = $self->overlimit('unsuspend');
      foreach my $part_export ( $self->cust_svc->part_svc->part_export ) {
        if ($part_export->option('overlimit_groups')) {
          my $old = new FS::svc_acct $self->hashref;
          my $groups = &{ $self->_fieldhandlers->{'usergroup'} }
                         ($self, $part_export->option('overlimit_groups'));
          $old->usergroup( $groups );
          $error ||= $part_export->export_replace($self, $old);
        }
      }
    }

    if ( $conf->exists("svc_acct-usage_unsuspend")) {
      $error ||= $self->cust_svc->cust_pkg->unsuspend;
    }
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "Error unsuspending: $error";
    }
  }

  warn "$me update successful; committing\n"
    if $DEBUG;
  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  '';

}


=item recharge HASHREF

  Increments usage columns by the amount specified in HASHREF as
  column=>amount pairs.

=cut

sub recharge {
  my ($self, $vhash) = @_;
   
  if ( $DEBUG ) {
    warn "[$me] recharge called on $self: ". Dumper($self).
         "\nwith vhash: ". Dumper($vhash);
  }

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;
  my $error = '';

  foreach my $column (keys %$vhash){
    $error ||= $self->_op_usage('+', $column, $vhash->{$column});
  }

  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
  }else{
    $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  }
  return $error;
}

=item is_rechargeable

Returns true if this svc_account can be "recharged" and false otherwise.

=cut

sub is_rechargable {
  my $self = shift;
  $self->seconds ne ''
    || $self->upbytes ne ''
    || $self->downbytes ne ''
    || $self->totalbytes ne '';
}

=item seconds_since TIMESTAMP

Returns the number of seconds this account has been online since TIMESTAMP,
according to the session monitor (see L<FS::Session>).

TIMESTAMP is specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=cut

#note: POD here, implementation in FS::cust_svc
sub seconds_since {
  my $self = shift;
  $self->cust_svc->seconds_since(@_);
}

=item seconds_since_sqlradacct TIMESTAMP_START TIMESTAMP_END

Returns the numbers of seconds this account has been online between
TIMESTAMP_START (inclusive) and TIMESTAMP_END (exclusive), according to an
external SQL radacct table, specified via sqlradius export.  Sessions which
started in the specified range but are still open are counted from session
start to the end of the range (unless they are over 1 day old, in which case
they are presumed missing their stop record and not counted).  Also, sessions
which end in the range but started earlier are counted from the start of the
range to session end.  Finally, sessions which start before the range but end
after are counted for the entire range.

TIMESTAMP_START and TIMESTAMP_END are specified as UNIX timestamps; see
L<perlfunc/"time">.  Also see L<Time::Local> and L<Date::Parse> for conversion
functions.

=cut

#note: POD here, implementation in FS::cust_svc
sub seconds_since_sqlradacct {
  my $self = shift;
  $self->cust_svc->seconds_since_sqlradacct(@_);
}

=item attribute_since_sqlradacct TIMESTAMP_START TIMESTAMP_END ATTRIBUTE

Returns the sum of the given attribute for all accounts (see L<FS::svc_acct>)
in this package for sessions ending between TIMESTAMP_START (inclusive) and
TIMESTAMP_END (exclusive).

TIMESTAMP_START and TIMESTAMP_END are specified as UNIX timestamps; see
L<perlfunc/"time">.  Also see L<Time::Local> and L<Date::Parse> for conversion
functions.

=cut

#note: POD here, implementation in FS::cust_svc
sub attribute_since_sqlradacct {
  my $self = shift;
  $self->cust_svc->attribute_since_sqlradacct(@_);
}

=item get_session_history TIMESTAMP_START TIMESTAMP_END

Returns an array of hash references of this customers login history for the
given time range.  (document this better)

=cut

sub get_session_history {
  my $self = shift;
  $self->cust_svc->get_session_history(@_);
}

=item get_cdrs TIMESTAMP_START TIMESTAMP_END [ 'OPTION' => 'VALUE ... ]

=cut

sub get_cdrs {
  my($self, $start, $end, %opt ) = @_;

  my $did = $self->username; #yup

  my $prefix = $opt{'default_prefix'}; #convergent.au '+61'

  my $for_update = $opt{'for_update'} ? 'FOR UPDATE' : '';

  #SELECT $for_update * FROM cdr
  #  WHERE calldate >= $start #need a conversion
  #    AND calldate <  $end   #ditto
  #    AND (    charged_party = "$did"
  #          OR charged_party = "$prefix$did" #if length($prefix);
  #          OR ( ( charged_party IS NULL OR charged_party = '' )
  #               AND
  #               ( src = "$did" OR src = "$prefix$did" ) # if length($prefix)
  #             )
  #        )
  #    AND ( freesidestatus IS NULL OR freesidestatus = '' )

  my $charged_or_src;
  if ( length($prefix) ) {
    $charged_or_src =
      " AND (    charged_party = '$did' 
              OR charged_party = '$prefix$did'
              OR ( ( charged_party IS NULL OR charged_party = '' )
                   AND
                   ( src = '$did' OR src = '$prefix$did' )
                 )
            )
      ";
  } else {
    $charged_or_src = 
      " AND (    charged_party = '$did' 
              OR ( ( charged_party IS NULL OR charged_party = '' )
                   AND
                   src = '$did'
                 )
            )
      ";

  }

  qsearch(
    'select'    => "$for_update *",
    'table'     => 'cdr',
    'hashref'   => {
                     #( freesidestatus IS NULL OR freesidestatus = '' )
                     'freesidestatus' => '',
                   },
    'extra_sql' => $charged_or_src,

  );

}

=item radius_groups

Returns all RADIUS groups for this account (see L<FS::radius_usergroup>).

=cut

sub radius_groups {
  my $self = shift;
  if ( $self->usergroup ) {
    confess "explicitly specified usergroup not an arrayref: ". $self->usergroup
      unless ref($self->usergroup) eq 'ARRAY';
    #when provisioning records, export callback runs in svc_Common.pm before
    #radius_usergroup records can be inserted...
    @{$self->usergroup};
  } else {
    map { $_->groupname }
      qsearch('radius_usergroup', { 'svcnum' => $self->svcnum } );
  }
}

=item clone_suspended

Constructor used by FS::part_export::_export_suspend fallback.  Document
better.

=cut

sub clone_suspended {
  my $self = shift;
  my %hash = $self->hash;
  $hash{_password} = join('',map($pw_set[ int(rand $#pw_set) ], (0..7) ) );
  new FS::svc_acct \%hash;
}

=item clone_kludge_unsuspend 

Constructor used by FS::part_export::_export_unsuspend fallback.  Document
better.

=cut

sub clone_kludge_unsuspend {
  my $self = shift;
  my %hash = $self->hash;
  $hash{_password} = '';
  new FS::svc_acct \%hash;
}

=item check_password 

Checks the supplied password against the (possibly encrypted) password in the
database.  Returns true for a successful authentication, false for no match.

Currently supported encryptions are: classic DES crypt() and MD5

=cut

sub check_password {
  my($self, $check_password) = @_;

  #remove old-style SUSPENDED kludge, they should be allowed to login to
  #self-service and pay up
  ( my $password = $self->_password ) =~ s/^\*SUSPENDED\* //;

  #eventually should check a "password-encoding" field
  if ( $password =~ /^(\*|!!?)$/ ) { #no self-service login
    return 0;
  } elsif ( length($password) < 13 ) { #plaintext
    $check_password eq $password;
  } elsif ( length($password) == 13 ) { #traditional DES crypt
    crypt($check_password, $password) eq $password;
  } elsif ( $password =~ /^\$1\$/ ) { #MD5 crypt
    unix_md5_crypt($check_password, $password) eq $password;
  } elsif ( $password =~ /^\$2a?\$/ ) { #Blowfish
    warn "Can't check password: Blowfish encryption not yet supported, svcnum".
         $self->svcnum. "\n";
    0;
  } else {
    warn "Can't check password: Unrecognized encryption for svcnum ".
         $self->svcnum. "\n";
    0;
  }

}

=item crypt_password [ DEFAULT_ENCRYPTION_TYPE ]

Returns an encrypted password, either by passing through an encrypted password
in the database or by encrypting a plaintext password from the database.

The optional DEFAULT_ENCRYPTION_TYPE parameter can be set to I<crypt> (classic
UNIX DES crypt), I<md5> (md5 crypt supported by most modern Linux and BSD
distrubtions), or (eventually) I<blowfish> (blowfish hashing supported by
OpenBSD, SuSE, other Linux distibutions with pam_unix2, etc.).  The default
encryption type is only used if the password is not already encrypted in the
database.

=cut

sub crypt_password {
  my $self = shift;
  #eventually should check a "password-encoding" field
  if ( length($self->_password) == 13
       || $self->_password =~ /^\$(1|2a?)\$/
       || $self->_password =~ /^(\*|NP|\*LK\*|!!?)$/
     )
  {
    $self->_password;
  } else {
    my $encryption = ( scalar(@_) && $_[0] ) ? shift : 'crypt';
    if ( $encryption eq 'crypt' ) {
      crypt(
        $self->_password,
        $saltset[int(rand(64))].$saltset[int(rand(64))]
      );
    } elsif ( $encryption eq 'md5' ) {
      unix_md5_crypt( $self->_password );
    } elsif ( $encryption eq 'blowfish' ) {
      croak "unknown encryption method $encryption";
    } else {
      croak "unknown encryption method $encryption";
    }
  }
}

=item ldap_password [ DEFAULT_ENCRYPTION_TYPE ]

Returns an encrypted password in "LDAP" format, with a curly-bracked prefix
describing the format, for example, "{CRYPT}94pAVyK/4oIBk" or
"{PLAIN-MD5}5426824942db4253f87a1009fd5d2d4f".

The optional DEFAULT_ENCRYPTION_TYPE is not yet used, but the idea is for it
to work the same as the B</crypt_password> method.

=cut

sub ldap_password {
  my $self = shift;
  #eventually should check a "password-encoding" field
  if ( length($self->_password) == 13 ) { #crypt
    return '{CRYPT}'. $self->_password;
  } elsif ( $self->_password =~ /^\$1\$(.*)$/ && length($1) == 31 ) { #passwdMD5
    return '{MD5}'. $1;
  } elsif ( $self->_password =~ /^\$2a?\$(.*)$/ ) { #Blowfish
    die "Blowfish encryption not supported in this context, svcnum ".
        $self->svcnum. "\n";
  } elsif ( $self->_password =~ /^(\w{48})$/ ) { #LDAP SSHA
    return '{SSHA}'. $1;
  } elsif ( $self->_password =~ /^(\w{64})$/ ) { #LDAP NS-MTA-MD5
    return '{NS-MTA-MD5}'. $1;
  } else { #plaintext
    return '{PLAIN}'. $self->_password;
    #my $encryption = ( scalar(@_) && $_[0] ) ? shift : 'crypt';
    #if ( $encryption eq 'crypt' ) {
    #  return '{CRYPT}'. crypt(
    #    $self->_password,
    #    $saltset[int(rand(64))].$saltset[int(rand(64))]
    #  );
    #} elsif ( $encryption eq 'md5' ) {
    #  unix_md5_crypt( $self->_password );
    #} elsif ( $encryption eq 'blowfish' ) {
    #  croak "unknown encryption method $encryption";
    #} else {
    #  croak "unknown encryption method $encryption";
    #}
  }
}

=item domain_slash_username

Returns $domain/$username/

=cut

sub domain_slash_username {
  my $self = shift;
  $self->domain. '/'. $self->username. '/';
}

=item virtual_maildir

Returns $domain/maildirs/$username/

=cut

sub virtual_maildir {
  my $self = shift;
  $self->domain. '/maildirs/'. $self->username. '/';
}

=back

=head1 SUBROUTINES

=over 4

=item send_email

This is the FS::svc_acct job-queue-able version.  It still uses
FS::Misc::send_email under-the-hood.

=cut

sub send_email {
  my %opt = @_;

  eval "use FS::Misc qw(send_email)";
  die $@ if $@;

  $opt{mimetype} ||= 'text/plain';
  $opt{mimetype} .= '; charset="iso-8859-1"' unless $opt{mimetype} =~ /charset/;

  my $error = send_email(
    'from'         => $opt{from},
    'to'           => $opt{to},
    'subject'      => $opt{subject},
    'content-type' => $opt{mimetype},
    'body'         => [ map "$_\n", split("\n", $opt{body}) ],
  );
  die $error if $error;
}

=item check_and_rebuild_fuzzyfiles

=cut

sub check_and_rebuild_fuzzyfiles {
  my $dir = $FS::UID::conf_dir. "cache.". $FS::UID::datasrc;
  -e "$dir/svc_acct.username"
    or &rebuild_fuzzyfiles;
}

=item rebuild_fuzzyfiles

=cut

sub rebuild_fuzzyfiles {

  use Fcntl qw(:flock);

  my $dir = $FS::UID::conf_dir. "cache.". $FS::UID::datasrc;

  #username

  open(USERNAMELOCK,">>$dir/svc_acct.username")
    or die "can't open $dir/svc_acct.username: $!";
  flock(USERNAMELOCK,LOCK_EX)
    or die "can't lock $dir/svc_acct.username: $!";

  my @all_username = map $_->getfield('username'), qsearch('svc_acct', {});

  open (USERNAMECACHE,">$dir/svc_acct.username.tmp")
    or die "can't open $dir/svc_acct.username.tmp: $!";
  print USERNAMECACHE join("\n", @all_username), "\n";
  close USERNAMECACHE or die "can't close $dir/svc_acct.username.tmp: $!";

  rename "$dir/svc_acct.username.tmp", "$dir/svc_acct.username";
  close USERNAMELOCK;

}

=item all_username

=cut

sub all_username {
  my $dir = $FS::UID::conf_dir. "cache.". $FS::UID::datasrc;
  open(USERNAMECACHE,"<$dir/svc_acct.username")
    or die "can't open $dir/svc_acct.username: $!";
  my @array = map { chomp; $_; } <USERNAMECACHE>;
  close USERNAMECACHE;
  \@array;
}

=item append_fuzzyfiles USERNAME

=cut

sub append_fuzzyfiles {
  my $username = shift;

  &check_and_rebuild_fuzzyfiles;

  use Fcntl qw(:flock);

  my $dir = $FS::UID::conf_dir. "cache.". $FS::UID::datasrc;

  open(USERNAME,">>$dir/svc_acct.username")
    or die "can't open $dir/svc_acct.username: $!";
  flock(USERNAME,LOCK_EX)
    or die "can't lock $dir/svc_acct.username: $!";

  print USERNAME "$username\n";

  flock(USERNAME,LOCK_UN)
    or die "can't unlock $dir/svc_acct.username: $!";
  close USERNAME;

  1;
}



=item radius_usergroup_selector GROUPS_ARRAYREF [ SELECTNAME ]

=cut

sub radius_usergroup_selector {
  my $sel_groups = shift;
  my %sel_groups = map { $_=>1 } @$sel_groups;

  my $selectname = shift || 'radius_usergroup';

  my $dbh = dbh;
  my $sth = $dbh->prepare(
    'SELECT DISTINCT(groupname) FROM radius_usergroup ORDER BY groupname'
  ) or die $dbh->errstr;
  $sth->execute() or die $sth->errstr;
  my @all_groups = map { $_->[0] } @{$sth->fetchall_arrayref};

  my $html = <<END;
    <SCRIPT>
    function ${selectname}_doadd(object) {
      var myvalue = object.${selectname}_add.value;
      var optionName = new Option(myvalue,myvalue,false,true);
      var length = object.$selectname.length;
      object.$selectname.options[length] = optionName;
      object.${selectname}_add.value = "";
    }
    </SCRIPT>
    <SELECT MULTIPLE NAME="$selectname">
END

  foreach my $group ( @all_groups ) {
    $html .= qq(<OPTION VALUE="$group");
    if ( $sel_groups{$group} ) {
      $html .= ' SELECTED';
      $sel_groups{$group} = 0;
    }
    $html .= ">$group</OPTION>\n";
  }
  foreach my $group ( grep { $sel_groups{$_} } keys %sel_groups ) {
    $html .= qq(<OPTION VALUE="$group" SELECTED>$group</OPTION>\n);
  };
  $html .= '</SELECT>';

  $html .= qq!<BR><INPUT TYPE="text" NAME="${selectname}_add">!.
           qq!<INPUT TYPE="button" VALUE="Add new group" onClick="${selectname}_doadd(this.form)">!;

  $html;
}

=item reached_threshold

Performs some activities when svc_acct thresholds (such as number of seconds
remaining) are reached.  

=cut

sub reached_threshold {
  my %opt = @_;

  my $svc_acct = qsearchs('svc_acct', { 'svcnum' => $opt{'svcnum'} } );
  die "Cannot find svc_acct with svcnum " . $opt{'svcnum'} unless $svc_acct;

  if ( $opt{'op'} eq '+' ){
    $svc_acct->setfield( $opt{'column'}.'_threshold',
                         int($svc_acct->getfield($opt{'column'})
                             * ( $conf->exists('svc_acct-usage_threshold') 
                                 ? $conf->config('svc_acct-usage_threshold')/100
                                 : 0.80
                               )
                         )
                       );
    my $error = $svc_acct->replace;
    die $error if $error;
  }elsif ( $opt{'op'} eq '-' ){
    
    my $threshold = $svc_acct->getfield( $opt{'column'}.'_threshold' );
    return '' if ($threshold eq '' );

    $svc_acct->setfield( $opt{'column'}.'_threshold', 0 );
    my $error = $svc_acct->replace;
    die $error if $error; # email next time, i guess

    if ( $warning_template ) {
      eval "use FS::Misc qw(send_email)";
      die $@ if $@;

      my $cust_pkg  = $svc_acct->cust_svc->cust_pkg;
      my $cust_main = $cust_pkg->cust_main;

      my $to = join(', ', grep { $_ !~ /^(POST|FAX)$/ } 
                               $cust_main->invoicing_list,
                               ($opt{'to'} ? $opt{'to'} : ())
                   );

      my $mimetype = $warning_mimetype;
      $mimetype .= '; charset="iso-8859-1"' unless $opt{mimetype} =~ /charset/;

      my $body       =  $warning_template->fill_in( HASH => {
                        'custnum'   => $cust_main->custnum,
                        'username'  => $svc_acct->username,
                        'password'  => $svc_acct->_password,
                        'first'     => $cust_main->first,
                        'last'      => $cust_main->getfield('last'),
                        'pkg'       => $cust_pkg->part_pkg->pkg,
                        'column'    => $opt{'column'},
                        'amount'    => $opt{'column'} =~/bytes/
                                       ? FS::UI::bytecount::display_bytecount($svc_acct->getfield($opt{'column'}))
                                       : $svc_acct->getfield($opt{'column'}),
                        'threshold' => $opt{'column'} =~/bytes/
                                       ? FS::UI::bytecount::display_bytecount($threshold)
                                       : $threshold,
                      } );


      my $error = send_email(
        'from'         => $warning_from,
        'to'           => $to,
        'subject'      => $warning_subject,
        'content-type' => $mimetype,
        'body'         => [ map "$_\n", split("\n", $body) ],
      );
      die $error if $error;
    }
  }else{
    die "unknown op: " . $opt{'op'};
  }
}

=back

=head1 BUGS

The $recref stuff in sub check should be cleaned up.

The suspend, unsuspend and cancel methods update the database, but not the
current object.  This is probably a bug as it's unexpected and
counterintuitive.

radius_usergroup_selector?  putting web ui components in here?  they should
probably live somewhere else...

insertion of RADIUS group stuff in insert could be done with child_objects now
(would probably clean up export of them too)

=head1 SEE ALSO

L<FS::svc_Common>, edit/part_svc.cgi from an installed web interface,
export.html from the base documentation, L<FS::Record>, L<FS::Conf>,
L<FS::cust_svc>, L<FS::part_svc>, L<FS::cust_pkg>, L<FS::queue>,
L<freeside-queued>), L<FS::svc_acct_pop>,
schema.html from the base documentation.

=cut

=item domain_select_hash %OPTIONS

Returns a hash SVCNUM => DOMAIN ...  representing the domains this customer
may at present purchase.

Currently available options are: I<pkgnum> I<svcpart>

=cut

sub domain_select_hash {
  my ($self, %options) = @_;
  my %domains = ();
  my $part_svc;
  my $cust_pkg;

  if (ref($self)) {
    $part_svc = $self->part_svc;
    $cust_pkg = $self->cust_svc->cust_pkg
      if $self->cust_svc;
  }

  $part_svc = qsearchs('part_svc', { 'svcpart' => $options{svcpart} })
    if $options{'svcpart'};

  $cust_pkg = qsearchs('cust_pkg', { 'pkgnum' => $options{pkgnum} })
    if $options{'pkgnum'};

  if ($part_svc && ( $part_svc->part_svc_column('domsvc')->columnflag eq 'S'
                  || $part_svc->part_svc_column('domsvc')->columnflag eq 'F')) {
    %domains = map { $_->svcnum => $_->domain }
               map { qsearchs('svc_domain', { 'svcnum' => $_ }) }
               split(',', $part_svc->part_svc_column('domsvc')->columnvalue);
  }elsif ($cust_pkg && !$conf->exists('svc_acct-alldomains') ) {
    %domains = map { $_->svcnum => $_->domain }
               map { qsearchs('svc_domain', { 'svcnum' => $_->svcnum }) }
               map { qsearch('cust_svc', { 'pkgnum' => $_->pkgnum } ) }
               qsearch('cust_pkg', { 'custnum' => $cust_pkg->custnum });
  }else{
    %domains = map { $_->svcnum => $_->domain } qsearch('svc_domain', {} );
  }

  if ($part_svc && $part_svc->part_svc_column('domsvc')->columnflag eq 'D') {
    my $svc_domain = qsearchs('svc_domain',
      { 'svcnum' => $part_svc->part_svc_column('domsvc')->columnvalue } );
    if ( $svc_domain ) {
      $domains{$svc_domain->svcnum}  = $svc_domain->domain;
    }else{
      warn "unknown svc_domain.svcnum for part_svc_column domsvc: ".
           $part_svc->part_svc_column('domsvc')->columnvalue;

    }
  }

  (%domains);
}

1;

