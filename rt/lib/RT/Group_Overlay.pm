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
# Released under the terms of version 2 of the GNU Public License

=head1 NAME

  RT::Group - RT\'s group object

=head1 SYNOPSIS

  use RT::Group;
my $group = new RT::Group($CurrentUser);

=head1 DESCRIPTION

An RT group object.

=head1 AUTHOR

Jesse Vincent, jesse@bestpractical.com

=head1 SEE ALSO

RT

=head1 METHODS


=begin testing

# {{{ Tests
ok (require RT::Group);

ok (my $group = RT::Group->new($RT::SystemUser), "instantiated a group object");
ok (my ($id, $msg) = $group->CreateUserDefinedGroup( Name => 'TestGroup', Description => 'A test group',
                    ), 'Created a new group');
ok ($id != 0, "Group id is $id");
ok ($group->Name eq 'TestGroup', "The group's name is 'TestGroup'");
my $ng = RT::Group->new($RT::SystemUser);

ok($ng->LoadUserDefinedGroup('TestGroup'), "Loaded testgroup");
ok(($ng->id == $group->id), "Loaded the right group");


ok (($id,$msg) = $ng->AddMember('1'), "Added a member to the group");
ok($id, $msg);
ok (($id,$msg) = $ng->AddMember('2' ), "Added a member to the group");
ok($id, $msg);
ok (($id,$msg) = $ng->AddMember('3' ), "Added a member to the group");
ok($id, $msg);

# Group 1 now has members 1, 2 ,3

my $group_2 = RT::Group->new($RT::SystemUser);
ok (my ($id_2, $msg_2) = $group_2->CreateUserDefinedGroup( Name => 'TestGroup2', Description => 'A second test group'), , 'Created a new group');
ok ($id_2 != 0, "Created group 2 ok- $msg_2 ");
ok (($id,$msg) = $group_2->AddMember($ng->PrincipalId), "Made TestGroup a member of testgroup2");
ok($id, $msg);
ok (($id,$msg) = $group_2->AddMember('1' ), "Added  member RT_System to the group TestGroup2");
ok($id, $msg);

# Group 2 how has 1, g1->{1, 2,3}

my $group_3 = RT::Group->new($RT::SystemUser);
ok (($id_3, $msg) = $group_3->CreateUserDefinedGroup( Name => 'TestGroup3', Description => 'A second test group'), 'Created a new group');
ok ($id_3 != 0, "Created group 3 ok - $msg");
ok (($id,$msg) =$group_3->AddMember($group_2->PrincipalId), "Made TestGroup a member of testgroup2");
ok($id, $msg);

# g3 now has g2->{1, g1->{1,2,3}}

my $principal_1 = RT::Principal->new($RT::SystemUser);
$principal_1->Load('1');

my $principal_2 = RT::Principal->new($RT::SystemUser);
$principal_2->Load('2');

ok (($id,$msg) = $group_3->AddMember('1' ), "Added  member RT_System to the group TestGroup2");
ok($id, $msg);

# g3 now has 1, g2->{1, g1->{1,2,3}}

ok($group_3->HasMember($principal_2) == undef, "group 3 doesn't have member 2");
ok($group_3->HasMemberRecursively($principal_2), "group 3 has member 2 recursively");
ok($ng->HasMember($principal_2) , "group ".$ng->Id." has member 2");
my ($delid , $delmsg) =$ng->DeleteMember($principal_2->Id);
ok ($delid !=0, "Sucessfully deleted it-".$delid."-".$delmsg);

#Gotta reload the group objects, since we've been messing with various internals.
# we shouldn't need to do this.
#$ng->LoadUserDefinedGroup('TestGroup');
#$group_2->LoadUserDefinedGroup('TestGroup2');
#$group_3->LoadUserDefinedGroup('TestGroup');

# G1 now has 1, 3
# Group 2 how has 1, g1->{1, 3}
# g3 now has  1, g2->{1, g1->{1, 3}}

ok(!$ng->HasMember($principal_2)  , "group ".$ng->Id." no longer has member 2");
ok($group_3->HasMemberRecursively($principal_2) == undef, "group 3 doesn't have member 2");
ok($group_2->HasMemberRecursively($principal_2) == undef, "group 2 doesn't have member 2");
ok($ng->HasMember($principal_2) == undef, "group 1 doesn't have member 2");;
ok($group_3->HasMemberRecursively($principal_2) == undef, "group 3 has member 2 recursively");

# }}}

=end testing



=cut

use strict;
no warnings qw(redefine);

use RT::Users;
use RT::GroupMembers;
use RT::Principals;
use RT::ACL;

use vars qw/$RIGHTS/;

$RIGHTS = {
    AdminGroup           => 'Modify group metadata or delete group',  # loc_pair
    AdminGroupMembership =>
      'Modify membership roster for this group',                      # loc_pair
    ModifyOwnMembership => 'Join or leave this group'                 # loc_pair
};

# Tell RT::ACE that this sort of object can get acls granted
$RT::ACE::OBJECT_TYPES{'RT::Group'} = 1;


#

# TODO: This should be refactored out into an RT::ACLedObject or something
# stuff the rights into a hash of rights that can exist.

foreach my $right ( keys %{$RIGHTS} ) {
    $RT::ACE::LOWERCASERIGHTNAMES{ lc $right } = $right;
}


=head2 AvailableRights

Returns a hash of available rights for this object. The keys are the right names and the values are a description of what the rights do

=cut

sub AvailableRights {
    my $self = shift;
    return($RIGHTS);
}


# {{{ sub SelfDescription

=head2 SelfDescription

Returns a user-readable description of what this group is for and what it's named.

=cut

sub SelfDescription {
	my $self = shift;
	if ($self->Domain eq 'ACLEquivalence') {
		my $user = RT::Principal->new($self->CurrentUser);
		$user->Load($self->Instance);
		return $self->loc("user [_1]",$user->Object->Name);
	}
	elsif ($self->Domain eq 'UserDefined') {
		return $self->loc("group '[_1]'",$self->Name);
	}
	elsif ($self->Domain eq 'Personal') {
		my $user = RT::User->new($self->CurrentUser);
		$user->Load($self->Instance);
		return $self->loc("personal group '[_1]' for user '[_2]'",$self->Name, $user->Name);
	}
	elsif ($self->Domain eq 'RT::System-Role') {
		return $self->loc("system [_1]",$self->Type);
	}
	elsif ($self->Domain eq 'RT::Queue-Role') {
		my $queue = RT::Queue->new($self->CurrentUser);
		$queue->Load($self->Instance);
		return $self->loc("queue [_1] [_2]",$queue->Name, $self->Type);
	}
	elsif ($self->Domain eq 'RT::Ticket-Role') {
		return $self->loc("ticket #[_1] [_2]",$self->Instance, $self->Type);
	}
	elsif ($self->Domain eq 'SystemInternal') {
		return $self->loc("system group '[_1]'",$self->Type);
	}
	else {
		return $self->loc("undescribed group [_1]",$self->Id);
	}
}

# }}}

# {{{ sub Load 

=head2 Load ID

Load a group object from the database. Takes a single argument.
If the argument is numerical, load by the column 'id'. Otherwise, 
complain and return.

=cut

sub Load {
    my $self       = shift;
    my $identifier = shift || return undef;

    #if it's an int, load by id. otherwise, load by name.
    if ( $identifier !~ /\D/ ) {
        $self->SUPER::LoadById($identifier);
    }
    else {
        $RT::Logger->crit("Group -> Load called with a bogus argument");
        return undef;
    }
}

# }}}

# {{{ sub LoadUserDefinedGroup 

=head2 LoadUserDefinedGroup NAME

Loads a system group from the database. The only argument is
the group's name.


=cut

sub LoadUserDefinedGroup {
    my $self       = shift;
    my $identifier = shift;

        $self->LoadByCols( "Domain" => 'UserDefined',
                           "Name" => $identifier );
}

# }}}

# {{{ sub LoadACLEquivalenceGroup 

=head2 LoadACLEquivalenceGroup  PRINCIPAL

Loads a user's acl equivalence group. Takes a principal object.
ACL equivalnce groups are used to simplify the acl system. Each user
has one group that only he is a member of. Rights granted to the user
are actually granted to that group. This greatly simplifies ACL checks.
While this results in a somewhat more complex setup when creating users
and granting ACLs, it _greatly_ simplifies acl checks.



=cut

sub LoadACLEquivalenceGroup {
    my $self       = shift;
    my $princ = shift;

        $self->LoadByCols( "Domain" => 'ACLEquivalence',
                            "Type" => 'UserEquiv',
                           "Instance" => $princ->Id);
}

# }}}

# {{{ sub LoadPersonalGroup 

=head2 LoadPersonalGroup {Name => NAME, User => USERID}

Loads a personal group from the database. 

=cut

sub LoadPersonalGroup {
    my $self       = shift;
    my %args =  (   Name => undef,
                    User => undef,
                    @_);

        $self->LoadByCols( "Domain" => 'Personal',
                           "Instance" => $args{'User'},
                           "Type" => '',
                           "Name" => $args{'Name'} );
}

# }}}

# {{{ sub LoadSystemInternalGroup 

=head2 LoadSystemInternalGroup NAME

Loads a Pseudo group from the database. The only argument is
the group's name.


=cut

sub LoadSystemInternalGroup {
    my $self       = shift;
    my $identifier = shift;

        $self->LoadByCols( "Domain" => 'SystemInternal',
                           "Instance" => '',
                           "Name" => '',
                           "Type" => $identifier );
}

# }}}

# {{{ sub LoadTicketRoleGroup 

=head2 LoadTicketRoleGroup  { Ticket => TICKET_ID, Type => TYPE }

Loads a ticket group from the database. 

Takes a param hash with 2 parameters:

    Ticket is the TicketId we're curious about
    Type is the type of Group we're trying to load: 
        Requestor, Cc, AdminCc, Owner

=cut

sub LoadTicketRoleGroup {
    my $self       = shift;
    my %args = (Ticket => undef,
                Type => undef,
                @_);
        $self->LoadByCols( Domain => 'RT::Ticket-Role',
                           Instance =>$args{'Ticket'}, 
                           Type => $args{'Type'}
                           );
}

# }}}

# {{{ sub LoadQueueRoleGroup 

=head2 LoadQueueRoleGroup  { Queue => Queue_ID, Type => TYPE }

Loads a Queue group from the database. 

Takes a param hash with 2 parameters:

    Queue is the QueueId we're curious about
    Type is the type of Group we're trying to load: 
        Requestor, Cc, AdminCc, Owner

=cut

sub LoadQueueRoleGroup {
    my $self       = shift;
    my %args = (Queue => undef,
                Type => undef,
                @_);
        $self->LoadByCols( Domain => 'RT::Queue-Role',
                           Instance =>$args{'Queue'}, 
                           Type => $args{'Type'}
                           );
}

# }}}

# {{{ sub LoadSystemRoleGroup 

=head2 LoadSystemRoleGroup  Type

Loads a System group from the database. 

Takes a single param: Type

    Type is the type of Group we're trying to load: 
        Requestor, Cc, AdminCc, Owner

=cut

sub LoadSystemRoleGroup {
    my $self       = shift;
    my $type = shift;
        $self->LoadByCols( Domain => 'RT::System-Role',
                           Type => $type
                           );
}

# }}}

# {{{ sub Create
=head2 Create

You need to specify what sort of group you're creating by calling one of the other
Create_____ routines.

=cut

sub Create {
    my $self = shift;
    $RT::Logger->crit("Someone called RT::Group->Create. this method does not exist. someone's being evil");
    return(0,$self->loc('Permission Denied'));
}

# }}}

# {{{ sub _Create

=head2 _Create

Takes a paramhash with named arguments: Name, Description.

Returns a tuple of (Id, Message).  If id is 0, the create failed

=cut

sub _Create {
    my $self = shift;
    my %args = (
        Name        => undef,
        Description => undef,
        Domain      => undef,
        Type        => undef,
        Instance    => undef,
        InsideTransaction => undef,
        @_
    );

    $RT::Handle->BeginTransaction() unless ($args{'InsideTransaction'});
    # Groups deal with principal ids, rather than user ids.
    # When creating this group, set up a principal Id for it.
    my $principal    = RT::Principal->new( $self->CurrentUser );
    my $principal_id = $principal->Create(
        PrincipalType => 'Group',
        ObjectId      => '0'
    );
    $principal->__Set(Field => 'ObjectId', Value => $principal_id);


    $self->SUPER::Create(
        id          => $principal_id,
        Name        => $args{'Name'},
        Description => $args{'Description'},
        Type        => $args{'Type'},
        Domain      => $args{'Domain'},
        Instance    => $args{'Instance'}
    );
    my $id = $self->Id;
    unless ($id) {
        return ( 0, $self->loc('Could not create group') );
    }

    # If we couldn't create a principal Id, get the fuck out.
    unless ($principal_id) {
        $RT::Handle->Rollback() unless ($args{'InsideTransaction'});
        $self->crit( "Couldn't create a Principal on new user create. Strange things are afoot at the circle K" );
        return ( 0, $self->loc('Could not create group') );
    }

    # Now we make the group a member of itself as a cached group member
    # this needs to exist so that group ACL checks don't fall over.
    # you're checking CachedGroupMembers to see if the principal in question
    # is a member of the principal the rights have been granted too

    # in the ordinary case, this would fail badly because it would recurse and add all the members of this group as 
    # cached members. thankfully, we're creating the group now...so it has no members.
    my $cgm = RT::CachedGroupMember->new($self->CurrentUser);
    $cgm->Create(Group =>$self->PrincipalObj, Member => $self->PrincipalObj, ImmediateParent => $self->PrincipalObj);



    $RT::Handle->Commit() unless ($args{'InsideTransaction'});
    return ( $id, $self->loc("Group created") );
}

# }}}

# {{{ CreateUserDefinedGroup

=head2 CreateUserDefinedGroup { Name => "name", Description => "Description"}

A helper subroutine which creates a system group 

Returns a tuple of (Id, Message).  If id is 0, the create failed

=cut

sub CreateUserDefinedGroup {
    my $self = shift;

    unless ( $self->CurrentUserHasRight('AdminGroup') ) {
        $RT::Logger->warning( $self->CurrentUser->Name
              . " Tried to create a group without permission." );
        return ( 0, $self->loc('Permission Denied') );
    }

    return($self->_Create( Domain => 'UserDefined', Type => '', Instance => '', @_));
}

# }}}

# {{{ _CreateACLEquivalenceGroup

=head2 _CreateACLEquivalenceGroup { Principal }

A helper subroutine which creates a group containing only 
an individual user. This gets used by the ACL system to check rights.
Yes, it denormalizes the data, but that's ok, as we totally win on performance.

Returns a tuple of (Id, Message).  If id is 0, the create failed

=cut

sub _CreateACLEquivalenceGroup { 
    my $self = shift;
    my $princ = shift;
 
      my $id = $self->_Create( Domain => 'ACLEquivalence', 
                           Type => 'UserEquiv',
                           Name => 'User '. $princ->Object->Id,
                           Description => 'ACL equiv. for user '.$princ->Object->Id,
                           Instance => $princ->Id,
                           InsideTransaction => 1);
      unless ($id) {
        $RT::Logger->crit("Couldn't create ACL equivalence group");
        return undef;
      }
    
       # We use stashuser so we don't get transactions inside transactions
       # and so we bypass all sorts of cruft we don't need
       my $aclstash = RT::GroupMember->new($self->CurrentUser);
       my ($stash_id, $add_msg) = $aclstash->_StashUser(Group => $self->PrincipalObj,
                                             Member => $princ);

      unless ($stash_id) {
        $RT::Logger->crit("Couldn't add the user to his own acl equivalence group:".$add_msg);
        # We call super delete so we don't get acl checked.
        $self->SUPER::Delete();
        return(undef);
      }
    return ($id);
}

# }}}

# {{{ CreatePersonalGroup

=head2 CreatePersonalGroup { PrincipalId => PRINCIPAL_ID, Name => "name", Description => "Description"}

A helper subroutine which creates a personal group. Generally,
personal groups are used for ACL delegation and adding to ticket roles
PrincipalId defaults to the current user's principal id.

Returns a tuple of (Id, Message).  If id is 0, the create failed

=cut

sub CreatePersonalGroup {
    my $self = shift;
    my %args = (
        Name        => undef,
        Description => undef,
        PrincipalId => $self->CurrentUser->PrincipalId,
        @_
    );

    if ( $self->CurrentUser->PrincipalId == $args{'PrincipalId'} ) {

        unless ( $self->CurrentUserHasRight('AdminOwnPersonalGroups') ) {
            $RT::Logger->warning( $self->CurrentUser->Name
                  . " Tried to create a group without permission." );
            return ( 0, $self->loc('Permission Denied') );
        }

    }
    else {
        unless ( $self->CurrentUserHasRight('AdminAllPersonalGroups') ) {
            $RT::Logger->warning( $self->CurrentUser->Name
                  . " Tried to create a group without permission." );
            return ( 0, $self->loc('Permission Denied') );
        }

    }

    return (
        $self->_Create(
            Domain      => 'Personal',
            Type        => '',
            Instance    => $args{'PrincipalId'},
            Name        => $args{'Name'},
            Description => $args{'Description'}
        )
    );
}

# }}}

# {{{ CreateRoleGroup 

=head2 CreateRoleGroup { Domain => DOMAIN, Type =>  TYPE, Instance => ID }

A helper subroutine which creates a  ticket group. (What RT 2.0 called Ticket watchers)
Type is one of ( "Requestor" || "Cc" || "AdminCc" || "Owner") 
Domain is one of (RT::Ticket-Role || RT::Queue-Role || RT::System-Role)
Instance is the id of the ticket or queue in question

This routine expects to be called from {Ticket||Queue}->CreateTicketGroups _inside of a transaction_

Returns a tuple of (Id, Message).  If id is 0, the create failed

=cut

sub CreateRoleGroup {
    my $self = shift;
    my %args = ( Instance => undef,
                 Type     => undef,
                 Domain   => undef,
                 @_ );
    unless ( $args{'Type'} =~ /^(?:Cc|AdminCc|Requestor|Owner)$/ ) {
        return ( 0, $self->loc("Invalid Group Type") );
    }


    return ( $self->_Create( Domain            => $args{'Domain'},
                             Instance          => $args{'Instance'},
                             Type              => $args{'Type'},
                             InsideTransaction => 1 ) );
}

# }}}

# {{{ sub Delete

=head2 Delete

Delete this object

=cut

sub Delete {
    my $self = shift;

    unless ( $self->CurrentUserHasRight('AdminGroup') ) {
        return ( 0, 'Permission Denied' );
    }

    $RT::Logger->crit("Deleting groups violates referential integrity until we go through and fix this");
    # TODO XXX 
   
    # Remove the principal object
    # Remove this group from anything it's a member of.
    # Remove all cached members of this group
    # Remove any rights granted to this group
    # remove any rights delegated by way of this group

    return ( $self->SUPER::Delete(@_) );
}

# }}}

=head2 SetDisabled BOOL

If passed a positive value, this group will be disabled. No rights it commutes or grants will be honored.
It will not appear in most group listings.

This routine finds all the cached group members that are members of this group  (recursively) and disables them.
=cut 

 # }}}

 sub SetDisabled {
     my $self = shift;
     my $val = shift;
    if ($self->Domain eq 'Personal') {
   		if ($self->CurrentUser->PrincipalId == $self->Instance) {
    		unless ( $self->CurrentUserHasRight('AdminOwnPersonalGroups')) {
        		return ( 0, $self->loc('Permission Denied') );
    		}
    	} else {
        	unless ( $self->CurrentUserHasRight('AdminAllPersonalGroups') ) {
   	    		 return ( 0, $self->loc('Permission Denied') );
    		}
    	}
	}
	else {
        unless ( $self->CurrentUserHasRight('AdminGroup') ) {
                 return (0, $self->loc('Permission Denied'));
    }
    }
    $RT::Handle->BeginTransaction();
    $self->PrincipalObj->SetDisabled($val);




    # Find all occurrences of this member as a member of this group
    # in the cache and nuke them, recursively.

    # The following code will delete all Cached Group members
    # where this member's group is _not_ the primary group 
    # (Ie if we're deleting C as a member of B, and B happens to be 
    # a member of A, will delete C as a member of A without touching
    # C as a member of B

    my $cached_submembers = RT::CachedGroupMembers->new( $self->CurrentUser );

    $cached_submembers->Limit( FIELD    => 'ImmediateParentId', OPERATOR => '=', VALUE    => $self->Id);

    #Clear the key cache. TODO someday we may want to just clear a little bit of the keycache space. 
    # TODO what about the groups key cache?
    RT::Principal->_InvalidateACLCache();



    while ( my $item = $cached_submembers->Next() ) {
        my $del_err = $item->SetDisabled($val);
        unless ($del_err) {
            $RT::Handle->Rollback();
            $RT::Logger->warning("Couldn't disable cached group submember ".$item->Id);
            return (undef);
        }
    }

    $RT::Handle->Commit();
    return (1, $self->loc("Succeeded"));

}

# }}}



sub Disabled {
    my $self = shift;
    $self->PrincipalObj->Disabled(@_);
}


# {{{ DeepMembersObj

=head2 DeepMembersObj

Returns an RT::CachedGroupMembers object of this group's members.

=cut

sub DeepMembersObj {
    my $self = shift;
    my $members_obj = RT::CachedGroupMembers->new( $self->CurrentUser );

    #If we don't have rights, don't include any results
    # TODO XXX  WHY IS THERE NO ACL CHECK HERE?
    $members_obj->LimitToMembersOfGroup( $self->PrincipalId );

    return ( $members_obj );

}

# }}}

# {{{ UserMembersObj

=head2 UserMembersObj

Returns an RT::Users object of this group's members, including
all members of subgroups

=cut

sub UserMembersObj {
    my $self = shift;

    my $users = RT::Users->new($self->CurrentUser);

    #If we don't have rights, don't include any results
    # TODO XXX  WHY IS THERE NO ACL CHECK HERE?

    my $principals = $users->NewAlias('Principals');

    $users->Join(ALIAS1 => 'main', FIELD1 => 'id',
                 ALIAS2 => $principals, FIELD2 => 'ObjectId');
    $users->Limit(ALIAS =>$principals,
                  FIELD => 'PrincipalType', OPERATOR => '=', VALUE => 'User');

    my $cached_members = $users->NewAlias('CachedGroupMembers');
    $users->Join(ALIAS1 => $cached_members, FIELD1 => 'MemberId',
                 ALIAS2 => $principals, FIELD2 => 'id');
    $users->Limit(ALIAS => $cached_members, 
                  FIELD => 'GroupId',
                  OPERATOR => '=',
                  VALUE => $self->PrincipalId);


    return ( $users);

}

# }}}

# {{{ MembersObj

=head2 MembersObj

Returns an RT::CachedGroupMembers object of this group's members.

=cut

sub MembersObj {
    my $self = shift;
    my $members_obj = RT::GroupMembers->new( $self->CurrentUser );

    #If we don't have rights, don't include any results
    # TODO XXX  WHY IS THERE NO ACL CHECK HERE?
    $members_obj->LimitToMembersOfGroup( $self->PrincipalId );

    return ( $members_obj );

}

# }}}

# {{{ MemberEmailAddresses

=head2 MemberEmailAddresses

Returns an array of the email addresses of all of this group's members


=cut

sub MemberEmailAddresses {
    my $self = shift;

    my %addresses;
    my $members = $self->UserMembersObj();
    while (my $member = $members->Next) {
        $addresses{$member->EmailAddress} = 1;
    }
    return(sort keys %addresses);
}

# }}}

# {{{ MemberEmailAddressesAsString

=head2 MemberEmailAddressesAsString

Returns a comma delimited string of the email addresses of all users 
who are members of this group.

=cut


sub MemberEmailAddressesAsString {
    my $self = shift;
    return (join(', ', $self->MemberEmailAddresses));
}

# }}}

# {{{ AddMember

=head2 AddMember PRINCIPAL_ID

AddMember adds a principal to this group.  It takes a single principal id.
Returns a two value array. the first value is true on successful 
addition or 0 on failure.  The second value is a textual status msg.

=cut

sub AddMember {
    my $self       = shift;
    my $new_member = shift;



    if ($self->Domain eq 'Personal') {
   		if ($self->CurrentUser->PrincipalId == $self->Instance) {
    		unless ( $self->CurrentUserHasRight('AdminOwnPersonalGroups')) {
        		return ( 0, $self->loc('Permission Denied') );
    		}
    	} else {
        	unless ( $self->CurrentUserHasRight('AdminAllPersonalGroups') ) {
   	    		 return ( 0, $self->loc('Permission Denied') );
    		}
    	}
	}
	
	else {	
    # We should only allow membership changes if the user has the right 
    # to modify group membership or the user is the principal in question
    # and the user has the right to modify his own membership
    unless ( ($new_member == $self->CurrentUser->PrincipalId &&
	      $self->CurrentUserHasRight('ModifyOwnMembership') ) ||
	      $self->CurrentUserHasRight('AdminGroupMembership') ) {
        #User has no permission to be doing this
        return ( 0, $self->loc("Permission Denied") );
    }

  	} 
    $self->_AddMember(PrincipalId => $new_member);
}

# A helper subroutine for AddMember that bypasses the ACL checks
# this should _ONLY_ ever be called from Ticket/Queue AddWatcher
# when we want to deal with groups according to queue rights
# In the dim future, this will all get factored out and life
# will get better	

# takes a paramhash of { PrincipalId => undef, InsideTransaction }

sub _AddMember {
    my $self = shift;
    my %args = ( PrincipalId => undef,
                 InsideTransaction => undef,
                 @_);
    my $new_member = $args{'PrincipalId'};

    unless ($self->Id) {
        $RT::Logger->crit("Attempting to add a member to a group which wasn't loaded. 'oops'");
        return(0, $self->loc("Group not found"));
    }

    unless ($new_member =~ /^\d+$/) {
        $RT::Logger->crit("_AddMember called with a parameter that's not an integer.");
    }


    my $new_member_obj = RT::Principal->new( $self->CurrentUser );
    $new_member_obj->Load($new_member);


    unless ( $new_member_obj->Id ) {
        $RT::Logger->debug("Couldn't find that principal");
        return ( 0, $self->loc("Couldn't find that principal") );
    }

    if ( $self->HasMember( $new_member_obj ) ) {

        #User is already a member of this group. no need to add it
        return ( 0, $self->loc("Group already has member") );
    }
    if ( $new_member_obj->IsGroup &&
         $new_member_obj->Object->HasMemberRecursively($self->PrincipalObj) ) {

        #This group can't be made to be a member of itself
        return ( 0, $self->loc("Groups can't be members of their members"));
    }


    my $member_object = RT::GroupMember->new( $self->CurrentUser );
    my $id = $member_object->Create(
        Member => $new_member_obj,
        Group => $self->PrincipalObj,
        InsideTransaction => $args{'InsideTransaction'}
    );
    if ($id) {
        return ( 1, $self->loc("Member added") );
    }
    else {
        return(0, $self->loc("Couldn't add member to group"));
    }
}
# }}}

# {{{ HasMember

=head2 HasMember RT::Principal

Takes an RT::Principal object returns a GroupMember Id if that user is a 
member of this group.
Returns undef if the user isn't a member of the group or if the current
user doesn't have permission to find out. Arguably, it should differentiate
between ACL failure and non membership.

=cut

sub HasMember {
    my $self    = shift;
    my $principal = shift;


    unless (UNIVERSAL::isa($principal,'RT::Principal')) {
        $RT::Logger->crit("Group::HasMember was called with an argument that".
                          "isn't an RT::Principal. It's $principal");
        return(undef);
    }

    my $member_obj = RT::GroupMember->new( $self->CurrentUser );
    $member_obj->LoadByCols( MemberId => $principal->id, 
                             GroupId => $self->PrincipalId );

    #If we have a member object
    if ( defined $member_obj->id ) {
        return ( $member_obj->id );
    }

    #If Load returns no objects, we have an undef id. 
    else {
        #$RT::Logger->debug($self." does not contain principal ".$principal->id);
        return (undef);
    }
}

# }}}

# {{{ HasMemberRecursively

=head2 HasMemberRecursively RT::Principal

Takes an RT::Principal object and returns true if that user is a member of 
this group.
Returns undef if the user isn't a member of the group or if the current
user doesn't have permission to find out. Arguably, it should differentiate
between ACL failure and non membership.

=cut

sub HasMemberRecursively {
    my $self    = shift;
    my $principal = shift;

    unless (UNIVERSAL::isa($principal,'RT::Principal')) {
        $RT::Logger->crit("Group::HasMemberRecursively was called with an argument that".
                          "isn't an RT::Principal. It's $principal");
        return(undef);
    }
    my $member_obj = RT::CachedGroupMember->new( $self->CurrentUser );
    $member_obj->LoadByCols( MemberId => $principal->Id,
                             GroupId => $self->PrincipalId ,
                             Disabled => 0
                             );

    #If we have a member object
    if ( defined $member_obj->id ) {
        return ( 1);
    }

    #If Load returns no objects, we have an undef id. 
    else {
        return (undef);
    }
}

# }}}

# {{{ DeleteMember

=head2 DeleteMember PRINCIPAL_ID

Takes the principal id of a current user or group.
If the current user has apropriate rights,
removes that GroupMember from this group.
Returns a two value array. the first value is true on successful 
addition or 0 on failure.  The second value is a textual status msg.

=cut

sub DeleteMember {
    my $self   = shift;
    my $member_id = shift;


    # We should only allow membership changes if the user has the right 
    # to modify group membership or the user is the principal in question
    # and the user has the right to modify his own membership

    if ($self->Domain eq 'Personal') {
   		if ($self->CurrentUser->PrincipalId == $self->Instance) {
    		unless ( $self->CurrentUserHasRight('AdminOwnPersonalGroups')) {
        		return ( 0, $self->loc('Permission Denied') );
    		}
    	} else {
        	unless ( $self->CurrentUserHasRight('AdminAllPersonalGroups') ) {
   	    		 return ( 0, $self->loc('Permission Denied') );
    		}
    	}
	}
	else {
    unless ( (($member_id == $self->CurrentUser->PrincipalId) &&
	      $self->CurrentUserHasRight('ModifyOwnMembership') ) ||
	      $self->CurrentUserHasRight('AdminGroupMembership') ) {
        #User has no permission to be doing this
        return ( 0, $self->loc("Permission Denied") );
    }
	}
    $self->_DeleteMember($member_id);
}

# A helper subroutine for DeleteMember that bypasses the ACL checks
# this should _ONLY_ ever be called from Ticket/Queue  DeleteWatcher
# when we want to deal with groups according to queue rights
# In the dim future, this will all get factored out and life
# will get better	

sub _DeleteMember {
    my $self = shift;
    my $member_id = shift;

    my $member_obj =  RT::GroupMember->new( $self->CurrentUser );
    
    $member_obj->LoadByCols( MemberId  => $member_id,
                             GroupId => $self->PrincipalId);


    #If we couldn't load it, return undef.
    unless ( $member_obj->Id() ) {
        $RT::Logger->debug("Group has no member with that id");
        return ( 0,$self->loc( "Group has no such member" ));
    }

    #Now that we've checked ACLs and sanity, delete the groupmember
    my $val = $member_obj->Delete();

    if ($val) {
        return ( $val, $self->loc("Member deleted") );
    }
    else {
        $RT::Logger->debug("Failed to delete group ".$self->Id." member ". $member_id);
        return ( 0, $self->loc("Member not deleted" ));
    }
}

# }}}

# {{{ ACL Related routines

# {{{ sub _Set
sub _Set {
    my $self = shift;

	if ($self->Domain eq 'Personal') {
   		if ($self->CurrentUser->PrincipalId == $self->Instance) {
    		unless ( $self->CurrentUserHasRight('AdminOwnPersonalGroups')) {
        		return ( 0, $self->loc('Permission Denied') );
    		}
    	} else {
        	unless ( $self->CurrentUserHasRight('AdminAllPersonalGroups') ) {
   	    		 return ( 0, $self->loc('Permission Denied') );
    		}
    	}
	}
	else {
    	unless ( $self->CurrentUserHasRight('AdminGroup') ) {
        	return ( 0, $self->loc('Permission Denied') );
    	}
	}
    return ( $self->SUPER::_Set(@_) );
}

# }}}




=item CurrentUserHasRight RIGHTNAME

Returns true if the current user has the specified right for this group.


    TODO: we don't deal with membership visibility yet

=cut


sub CurrentUserHasRight {
    my $self = shift;
    my $right = shift;



    if ($self->Id && 
		$self->CurrentUser->HasRight( Object => $self,
										   Right => $right )) {
        return(1);
   }
    elsif ( $self->CurrentUser->HasRight(Object => $RT::System, Right =>  $right )) {
		return (1);
    } else {
        return(undef);
    }

}

# }}}




# {{{ Principal related routines

=head2 PrincipalObj

Returns the principal object for this user. returns an empty RT::Principal
if there's no principal object matching this user. 
The response is cached. PrincipalObj should never ever change.

=begin testing

ok(my $u = RT::Group->new($RT::SystemUser));
ok($u->Load(4), "Loaded the first user");
ok($u->PrincipalObj->ObjectId == 4, "user 4 is the fourth principal");
ok($u->PrincipalObj->PrincipalType eq 'Group' , "Principal 4 is a group");

=end testing

=cut


sub PrincipalObj {
    my $self = shift;
    unless ($self->{'PrincipalObj'} &&
            ($self->{'PrincipalObj'}->ObjectId == $self->Id) &&
            ($self->{'PrincipalObj'}->PrincipalType eq 'Group')) {

            $self->{'PrincipalObj'} = RT::Principal->new($self->CurrentUser);
            $self->{'PrincipalObj'}->LoadByCols('ObjectId' => $self->Id,
                                                'PrincipalType' => 'Group') ;
            }
    return($self->{'PrincipalObj'});
}


=head2 PrincipalId  

Returns this user's PrincipalId

=cut

sub PrincipalId {
    my $self = shift;
    return $self->Id;
}

# }}}
1;

