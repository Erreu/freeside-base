# BEGIN LICENSE BLOCK
# 
# Copyright (c) 1996-2003 Jesse Vincent <jesse@bestpractical.com>
# 
# (Except where explictly superceded by other copyright notices)
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
# Unless otherwise specified, all modifications, corrections or
# extensions to this work which alter its source code become the
# property of Best Practical Solutions, LLC when submitted for
# inclusion in the work.
# 
# 
# END LICENSE BLOCK
=head1 NAME 

RT::System

=head1 DESCRIPTION

RT::System is a simple global object used as a focal point for things
that are system-wide.

It works sort of like an RT::Record, except it's really a single object that has
an id of "1" when instantiated.

This gets used by the ACL system so that you can have rights for the scope "RT::System"

In the future, there will probably be other API goodness encapsulated here.

=cut


package RT::System;
use base qw /RT::Base/;
use strict;

use RT::ACL;
use vars qw/ $RIGHTS/;

# System rights are rights granted to the whole system
# XXX TODO Can't localize these outside of having an object around.
$RIGHTS = {
    SuperUser              => 'Do anything and everything',           # loc_pair
    AdminAllPersonalGroups =>
      "Create, delete and modify the members of any user's personal groups"
    ,                                                                 # loc_pair
    AdminOwnPersonalGroups =>
      'Create, delete and modify the members of personal groups',     # loc_pair
    AdminUsers     => 'Create, delete and modify users',              # loc_pair
    ModifySelf     => "Modify one's own RT account",                  # loc_pair
    DelegateRights =>
      "Delegate specific rights which have been granted to you."      # loc_pair
};

# Tell RT::ACE that this sort of object can get acls granted
$RT::ACE::OBJECT_TYPES{'RT::System'} = 1;

foreach my $right ( keys %{$RIGHTS} ) {
    $RT::ACE::LOWERCASERIGHTNAMES{ lc $right } = $right;
}


=head2 AvailableRights

Returns a hash of available rights for this object. The keys are the right names and the values are a description of what the rights do

=begin testing

my $s = RT::System->new($RT::SystemUser);
my $rights = $s->AvailableRights;
ok ($rights, "Rights defined");
ok ($rights->{'AdminUsers'},"AdminUsers right found");
ok ($rights->{'CreateTicket'},"CreateTicket right found");
ok ($rights->{'AdminGroupMembership'},"ModifyGroupMembers right found");
ok (!$rights->{'CasdasdsreateTicket'},"bogus right not found");



=end testing


=cut

sub AvailableRights {
    my $self = shift;

    my $queue = RT::Queue->new($RT::SystemUser);
    my $group = RT::Group->new($RT::SystemUser);

    my $qr =$queue->AvailableRights();
    my $gr = $group->AvailableRights();

    # Build a merged list of all system wide rights, queue rights and group rights.
    my %rights = (%{$RIGHTS}, %{$gr}, %{$qr});
    return(\%rights);
}


=head2 new

Create a new RT::System object. Really, you should be using $RT::System

=cut

                         
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless( $self, $class );


    return ($self);
}

=head2 id

Returns RT::System's id. It's 1. 


=begin testing

use RT::System;
my $sys = RT::System->new();
is( $sys->Id, 1);
is ($sys->id, 1);

=end testing


=cut

*Id = \&id;

sub id {
    return (1);
}

=head2 Load

Since this object is pretending to be an RT::Record, we need a load method.
It does nothing

=cut

sub Load {
	return (1);
}

eval "require RT::System_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/System_Vendor.pm});
eval "require RT::System_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/System_Local.pm});

1;
