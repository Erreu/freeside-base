package FS::part_export::forward_shellcommands;

use strict;
use vars qw(@ISA);
use FS::part_export;

@ISA = qw(FS::part_export);

sub rebless { shift; }

sub _export_insert {
  my($self) = shift;
  $self->_export_command('useradd', @_);
}

sub _export_delete {
  my($self) = shift;
  $self->_export_command('userdel', @_);
}

sub _export_command {
  my ( $self, $action, $svc_forward ) = (shift, shift, shift);
  my $command = $self->option($action);

  #set variable for the command
  no strict 'vars';
  {
    no strict 'refs';
    ${$_} = $svc_forward->getfield($_) foreach $svc_forward->fields;
  }

  my $svc_acct = $svc_forward->srcsvc_acct;
  $username = $svc_acct->username;
  $domain = $svc_acct->domain;
  if ($svc_forward->dstsvc_acct) {
    $destination = $svc_forward->dstsvc_acct->email;
  } else {
    $destination = $svc_forward->dst;
  }

  #done setting variables for the command

  $self->shellcommands_queue( $svc_forward->svcnum,
    user         => $self->option('user')||'root',
    host         => $self->machine,
    command      => eval(qq("$command")),
  );
}

sub _export_replace {
  my( $self, $new, $old ) = (shift, shift, shift);
  my $command = $self->option('usermod');
  
  #set variable for the command
  no strict 'vars';
  {
    no strict 'refs';
    ${"old_$_"} = $old->getfield($_) foreach $old->fields;
    ${"new_$_"} = $new->getfield($_) foreach $new->fields;
  }

  my $old_svc_acct = $old->srcsvc_acct;
  $old_username = $old_svc_acct->username;
  $old_domain = $old_svc_acct->domain;
  if ($old->dstsvc_acct) {
    $old_destination = $old->dstsvc_acct->email;
  } else {
    $old_destination = $old->dst;
  }

  my $new_svc_acct = $new->srcsvc_acct;
  $new_username = $new_svc_acct->username;
  $new_domain = $new_svc_acct->domain;
  if ($new->dstsvc) {
    $new_destination = $new->dstsvc_acct->email;
  } else {
    $new_destination = $new->dst;
  }

  #done setting variables for the command

  $self->shellcommands_queue( $new->svcnum,
    user         => $self->option('user')||'root',
    host         => $self->machine,
    command      => eval(qq("$command")),
  );
}

#a good idea to queue anything that could fail or take any time
sub shellcommands_queue {
  my( $self, $svcnum ) = (shift, shift);
  my $queue = new FS::queue {
    'svcnum' => $svcnum,
    'job'    => "FS::part_export::forward_shellcommands::ssh_cmd",
  };
  $queue->insert( @_ );
}

sub ssh_cmd { #subroutine, not method
  use Net::SSH '0.07';
  &Net::SSH::ssh_cmd( { @_ } );
}

#sub shellcommands_insert { #subroutine, not method
#}
#sub shellcommands_replace { #subroutine, not method
#}
#sub shellcommands_delete { #subroutine, not method
#}

