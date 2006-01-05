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
# This Action will resolve all members of a resolved group ticket

package RT::Action::ResolveMembers;
require RT::Action::Generic;
require RT::Links;

use strict;
use vars qw/@ISA/;
@ISA=qw(RT::Action::Generic);

#Do what we need to do and send it out.

#What does this type of Action does

# {{{ sub Describe 
sub Describe  {
  my $self = shift;
  return $self->loc("[_1] will resolve all members of a resolved group ticket.", ref $self);
}
# }}}


# {{{ sub Prepare 
sub Prepare  {
    # nothing to prepare
    return 1;
}
# }}}

sub Commit {
    my $self = shift;

    my $Links=RT::Links->new($RT::SystemUser);
    $Links->Limit(FIELD => 'Type', VALUE => 'MemberOf');
    $Links->Limit(FIELD => 'Target', VALUE => $self->TicketObj->id);

    while (my $Link=$Links->Next()) {
	# Todo: Try to deal with remote URIs as well
	next unless $Link->BaseURI->IsLocal;
	my $base=RT::Ticket->new($self->TicketObj->CurrentUser);
	# Todo: Only work if Base is a plain ticket num:
	$base->Load($Link->Base);
	# I'm afraid this might be a major bottleneck if ResolveGroupTicket is on.
        $base->Resolve;
    }
}


# Applicability checked in Commit.

# {{{ sub IsApplicable 
sub IsApplicable  {
  my $self = shift;
  1;  
  return 1;
}
# }}}

eval "require RT::Action::ResolveMembers_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Action/ResolveMembers_Vendor.pm});
eval "require RT::Action::ResolveMembers_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Action/ResolveMembers_Local.pm});

1;

