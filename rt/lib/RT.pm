# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2009 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
package RT;
use strict;
use RT::I18N;
use RT::CurrentUser;
use RT::System;

use vars qw($VERSION $System $SystemUser $Nobody $Handle $Logger
        $CORE_CONFIG_FILE
        $SITE_CONFIG_FILE
        $BasePath
        $EtcPath
        $VarPath
        $LocalPath
        $LocalEtcPath
        $LocalLexiconPath
        $LogDir
        $BinPath
        $MasonComponentRoot
        $MasonLocalComponentRoot
        $MasonDataDir
        $MasonSessionDir
);

$VERSION = '3.6.10';
$CORE_CONFIG_FILE = "/opt/rt3/etc/RT_Config.pm";
$SITE_CONFIG_FILE = "/opt/rt3/etc/RT_SiteConfig.pm";



$BasePath = '/opt/rt3';

$EtcPath = '/opt/rt3/etc';
$BinPath = '/opt/rt3/bin';
$VarPath = '/opt/rt3/var';
$LocalPath = '/opt/rt3/local';
$LocalEtcPath = '/opt/rt3/local/etc';
$LocalLexiconPath = '/opt/rt3/local/po';

# $MasonComponentRoot is where your rt instance keeps its mason html files

$MasonComponentRoot = '/var/www/freeside/rt';

# $MasonLocalComponentRoot is where your rt instance keeps its site-local
# mason html files.

$MasonLocalComponentRoot = '/opt/rt3/local/html';

# $MasonDataDir Where mason keeps its datafiles

$MasonDataDir = '/usr/local/etc/freeside/masondata';

# RT needs to put session data (for preserving state between connections
# via the web interface)
$MasonSessionDir = '/opt/rt3/var/session_data';



=head1 NAME

RT - Request Tracker

=head1 SYNOPSIS

A fully featured request tracker package

=head1 DESCRIPTION

=head2 LoadConfig

Load RT's config file.  First, the site configuration file
(C<RT_SiteConfig.pm>) is loaded, in order to establish overall site
settings like hostname and name of RT instance.  Then, the core
configuration file (C<RT_Config.pm>) is loaded to set fallback values
for all settings; it bases some values on settings from the site
configuration file.

In order for the core configuration to not override the site's
settings, the function C<Set> is used; it only sets values if they
have not been set already.

=cut

sub LoadConfig {
     local *Set = sub { $_[0] = $_[1] unless defined $_[0] }; 

    my $username = getpwuid($>);
    my $group = getgrgid($();
    my $message = <<EOF;

RT couldn't load RT config file %s as:
    user: $username 
    group: $group

The file is owned by user %s and group %s.  

This usually means that the user/group your webserver is running
as cannot read the file.  Be careful not to make the permissions
on this file too liberal, because it contains database passwords.
You may need to put the webserver user in the appropriate group
(%s) or change permissions be able to run succesfully.
EOF


    if ( -f "$SITE_CONFIG_FILE" ) {
        eval { require $SITE_CONFIG_FILE };
        if ($@) {
            my ($fileuid,$filegid) = (stat($SITE_CONFIG_FILE))[4,5];
            my $fileusername = getpwuid($fileuid);
            my $filegroup = getgrgid($filegid);
            my $errormessage = sprintf($message, $SITE_CONFIG_FILE,
                                       $fileusername, $filegroup, $filegroup);
            die ("$errormessage\n$@");
        }
    }
    eval { require $CORE_CONFIG_FILE };
    if ($@) {
        my ($fileuid,$filegid) = (stat($CORE_CONFIG_FILE))[4,5];
        my $fileusername = getpwuid($fileuid);
        my $filegroup = getgrgid($filegid);
        my $errormessage = sprintf($message, $CORE_CONFIG_FILE,
                                   $fileusername, $filegroup, $filegroup);
        die ("$errormessage\n$@") 
    }

    # RT::Essentials mistakenly recommends that WebPath be set to '/'.
    # If the user does that, do what they mean.
    $RT::WebPath = '' if ($RT::WebPath eq '/');

    $ENV{'TZ'} = $RT::Timezone if ($RT::Timezone);

    RT::I18N->Init;
}

=head2 Init

Conenct to the database, set up logging.

=cut

sub Init {

    CheckPerlRequirements();

    #Get a database connection
    ConnectToDatabase();

    #RT's system user is a genuine database user. its id lives here
    $SystemUser = new RT::CurrentUser();
    $SystemUser->LoadByName('RT_System');
    
    #RT's "nobody user" is a genuine database user. its ID lives here.
    $Nobody = new RT::CurrentUser();
    $Nobody->LoadByName('Nobody');
  
    $System = RT::System->new();

    InitClasses();
    InitLogging(); 
}


=head2 ConnectToDatabase

Get a database connection

=cut

sub ConnectToDatabase {
    require RT::Handle;
    unless ($Handle && $Handle->dbh && $Handle->dbh->ping) {
        $Handle = RT::Handle->new();
    } 
    $Handle->Connect();
}

=head2 InitLogging

Create the RT::Logger object. 

=cut

sub InitLogging {

    # We have to set the record separator ($, man perlvar)
    # or Log::Dispatch starts getting
    # really pissy, as some other module we use unsets it.

    $, = '';
    use Log::Dispatch 1.6;

    unless ($RT::Logger) {

    $RT::Logger = Log::Dispatch->new();

    my $simple_cb = sub {
        # if this code throw any warning we can get segfault
        no warnings;

        my %p = @_;

        my $frame = 0; # stack frame index
        # skip Log::* stack frames
        $frame++ while( caller($frame) && caller($frame) =~ /^Log::/ );

        my ($package, $filename, $line) = caller($frame);
        $p{message} =~ s/(?:\r*\n)+$//;
        my $str = "[".gmtime(time)."] [".$p{level}."]: $p{message} ($filename:$line)\n";

        if( $RT::LogStackTraces ) {
            $str .= "\nStack trace:\n";
            # skip calling of the Log::* subroutins
            $frame++ while( caller($frame) && (caller($frame))[3] =~ /^Log::/ );
            while( my ($package, $filename, $line, $sub) = caller($frame++) ) {
                $str .= "\t". $sub ."() called at $filename:$line\n";
            }
        }
        return $str;
    };

    my $syslog_cb = sub {
        my %p = @_;

        my $frame = 0; # stack frame index
        # skip Log::* stack frames
        $frame++ while( caller($frame) && caller($frame) =~ /^Log::/ );
        my ($package, $filename, $line) = caller($frame);

        # syswrite() cannot take utf8; turn it off here.
        Encode::_utf8_off($p{message});

        $p{message} =~ s/(?:\r*\n)+$//;
        if ($p{level} eq 'debug') {
            return "$p{message}\n"
        } else {
            return "$p{message} ($filename:$line)\n"
        }
    };
    
    if ($RT::LogToFile) {
        my ($filename, $logdir);
        if ($RT::LogToFileNamed =~ m![/\\]!) {
            # looks like an absolute path.
            $filename = $RT::LogToFileNamed;
            ($logdir) = $RT::LogToFileNamed =~ m!^(.*[/\\])!;
        }
        else {
            $filename = "$RT::LogDir/$RT::LogToFileNamed";
            $logdir = $RT::LogDir;
        }

        unless ( -d $logdir && ( ( -f $filename && -w $filename ) || -w $logdir ) ) {
            # localizing here would be hard when we don't have a current user yet
            die "Log file $filename couldn't be written or created.\n RT can't run.";
        }

        package Log::Dispatch::File;
        require Log::Dispatch::File;
        $RT::Logger->add(Log::Dispatch::File->new
                       ( name=>'rtlog',
                         min_level=> $RT::LogToFile,
                         filename=> $filename,
                         mode=>'append',
                         callbacks => $simple_cb,
                       ));
    }
    if ($RT::LogToScreen) {
        package Log::Dispatch::Screen;
        require Log::Dispatch::Screen;
        $RT::Logger->add(Log::Dispatch::Screen->new
                     ( name => 'screen',
                       min_level => $RT::LogToScreen,
                       callbacks => $simple_cb,
                       stderr => 1,
                     ));
    }
    if ($RT::LogToSyslog) {
        package Log::Dispatch::Syslog;
        require Log::Dispatch::Syslog;
        $RT::Logger->add(Log::Dispatch::Syslog->new
                     ( name => 'syslog',
                       ident => 'RT',
                       min_level => $RT::LogToSyslog,
                       callbacks => $syslog_cb,
                       stderr => 1,
                       @RT::LogToSyslogConf
                     ));
    }

    }

# {{{ Signal handlers

## This is the default handling of warnings and die'ings in the code
## (including other used modules - maybe except for errors catched by
## Mason).  It will log all problems through the standard logging
## mechanism (see above).

    $SIG{__WARN__} = sub {
        # The 'wide character' warnings has to be silenced for now, at least
        # until HTML::Mason offers a sane way to process both raw output and
        # unicode strings.
        # use 'goto &foo' syntax to hide ANON sub from stack
        if( index($_[0], 'Wide character in ') != 0 ) {
            unshift @_, $RT::Logger, qw(level warning message);
            goto &Log::Dispatch::log;
        }
    };

#When we call die, trap it and log->crit with the value of the die.

$SIG{__DIE__}  = sub {
    unless ($^S || !defined $^S ) {
        $RT::Handle->Rollback();
        $RT::Logger->crit("$_[0]");
    }
    die $_[0];
};

# }}}

}


sub CheckPerlRequirements {
    if ($^V < 5.008003) {
        die sprintf "RT requires Perl v5.8.3 or newer.  Your current Perl is v%vd\n", $^V; 
    }

    local ($@);
    eval { 
        my $x = ''; 
        my $y = \$x;
        require Scalar::Util; Scalar::Util::weaken($y);
    };
    if ($@) {
        die <<"EOF";

RT requires the Scalar::Util module be built with support for  the 'weaken'
function. 

It is sometimes the case that operating system upgrades will replace 
a working Scalar::Util with a non-working one. If your system was working
correctly up until now, this is likely the cause of the problem.

Please reinstall Scalar::Util, being careful to let it build with your C 
compiler. Ususally this is as simple as running the following command as
root.

    perl -MCPAN -e'install Scalar::Util'

EOF

    }
}


=head2 InitClasses

Load all modules that define base classes

=cut

sub InitClasses {
    require RT::Tickets;
    require RT::Transactions;
    require RT::Attachments;
    require RT::Users;
    require RT::Principals;
    require RT::CurrentUser;
    require RT::Templates;
    require RT::Queues;
    require RT::ScripActions;
    require RT::ScripConditions;
    require RT::Scrips;
    require RT::Groups;
    require RT::GroupMembers;
    require RT::CustomFields;
    require RT::CustomFieldValues;
    require RT::ObjectCustomFields;
    require RT::ObjectCustomFieldValues;
    require RT::Attributes;

    # on a cold server (just after restart) people could have an object
    # in the session, as we deserialize it so we never call constructor
    # of the class, so the list of accessible fields is empty and we die
    # with "Method xxx is not implemented in RT::SomeClass"
    $_->_BuildTableAttributes foreach qw(
        RT::Ticket
        RT::Transaction
        RT::Attachment
        RT::User
        RT::Principal
        RT::Template
        RT::Queue
        RT::ScripAction
        RT::ScripCondition
        RT::Scrip
        RT::Group
        RT::GroupMember
        RT::CustomField
        RT::CustomFieldValue
        RT::ObjectCustomField
        RT::ObjectCustomFieldValue
        RT::Attribute
    );
}

# }}}


sub SystemUser {
    return($SystemUser);
}	

sub Nobody {
    return ($Nobody);
}

=head1 BUGS

Please report them to rt-bugs@fsck.com, if you know what's broken and have at least 
some idea of what needs to be fixed.

If you're not sure what's going on, report them rt-devel@lists.bestpractical.com.

=head1 SEE ALSO

L<RT::StyleGuide>
L<DBIx::SearchBuilder>

=begin testing

ok ($RT::Nobody->Name() eq 'Nobody', "Nobody is nobody");
ok ($RT::Nobody->Name() ne 'root', "Nobody isn't named root");
ok ($RT::SystemUser->Name() eq 'RT_System', "The system user is RT_System");
ok ($RT::SystemUser->Name() ne 'noname', "The system user isn't noname");

=end testing

=cut

eval "require RT_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT_Vendor.pm});
eval "require RT_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT_Local.pm});

1;
