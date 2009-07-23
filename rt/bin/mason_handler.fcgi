#!/usr/bin/perl
# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2005 Best Practical Solutions, LLC 
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
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
package RT::Mason;

use strict;
use vars '$Handler';
use File::Basename;
require ('/opt/rt3/bin/webmux.pl');

# Enter CGI::Fast mode, which should also work as a vanilla CGI script.
require CGI::Fast;

RT::Init();

while ( my $cgi = CGI::Fast->new ) {
    # the whole point of fastcgi requires the env to get reset here..
    # So we must squash it again
    $ENV{'PATH'}   = '/bin:/usr/bin';
    $ENV{'CDPATH'} = '' if defined $ENV{'CDPATH'};
    $ENV{'SHELL'}  = '/bin/sh' if defined $ENV{'SHELL'};
    $ENV{'ENV'}    = '' if defined $ENV{'ENV'};
    $ENV{'IFS'}    = '' if defined $ENV{'IFS'};

    Module::Refresh->refresh if $RT::DevelMode;
    RT::ConnectToDatabase();

    if ( ( !$Handler->interp->comp_exists( $cgi->path_info ) )
        && ( $Handler->interp->comp_exists( $cgi->path_info . "/index.html" ) ) ) {
        $cgi->path_info( $cgi->path_info . "/index.html" );
    }

    eval { $Handler->handle_cgi_object($cgi); };
    if ($@) {
        $RT::Logger->crit($@);
    }
    RT::Interface::Web::Handler->CleanupRequest(); 

}

1;
