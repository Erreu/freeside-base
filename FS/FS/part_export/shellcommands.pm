package FS::part_export::shellcommands;

use vars qw(@ISA @saltset);
use String::ShellQuote;
use FS::part_export;

@ISA = qw(FS::part_export);

@saltset = ( 'a'..'z' , 'A'..'Z' , '0'..'9' , '.' , '/' );

sub rebless { shift; }

sub _export_insert {
  my($self) = shift;
  $self->_export_command('useradd', @_);
}

sub _export_delete {
  my($self) = shift;
  $self->_export_command('userdel', @_);
}

sub _export_suspend {
  my($self) = shift;
  $self->_export_command('suspend', @_);
}

sub _export_unsuspend {
  my($self) = shift;
  $self->_export_command('unsuspend', @_);
}

sub _export_command {
  my ( $self, $action, $svc_acct) = (shift, shift, shift);
  my $command = $self->option($action);
  return '' if $command =~ /^\s*$/;
  my $stdin = $self->option($action."_stdin");

  no strict 'vars';
  {
    no strict 'refs';
    ${$_} = $svc_acct->getfield($_) foreach $svc_acct->fields;

    my $count = 1;
    foreach my $acct_snarf ( $svc_acct->acct_snarf ) {
      ${"snarf_$_$count"} = shell_quote( $acct_snarf->get($_) )
        foreach qw( machine username _password );
      $count++;
    }
  }

  my $cust_pkg = $svc_acct->cust_svc->cust_pkg;
  if ( $cust_pkg ) {
    $email = ( grep { $_ ne 'POST' } $cust_pkg->cust_main->invoicing_list )[0];
  } else {
    $email = '';
  }

  $finger = shell_quote $finger;
  $quoted_password = shell_quote $_password;
  $domain = $svc_acct->domain;

  #eventually should check a "password-encoding" field
  if ( length($svc_acct->_password) == 13
       || $svc_acct->_password =~ /^\$(1|2a?)\$/ ) {
    $crypt_password = shell_quote $svc_acct->_password;
  } else {
    $crypt_password = crypt(
      $svc_acct->_password,
      $saltset[int(rand(64))].$saltset[int(rand(64))]
    );
  }

  $self->shellcommands_queue( $svc_acct->svcnum,
    user         => $self->option('user')||'root',
    host         => $self->machine,
    command      => eval(qq("$command")),
    stdin_string => eval(qq("$stdin")),
  );
}

sub _export_replace {
  my($self, $new, $old ) = (shift, shift, shift);
  my $command = $self->option('usermod');
  my $stdin = $self->option('usermod_stdin');
  no strict 'vars';
  {
    no strict 'refs';
    ${"old_$_"} = $old->getfield($_) foreach $old->fields;
    ${"new_$_"} = $new->getfield($_) foreach $new->fields;
  }
  $new_finger = shell_quote $new_finger;
  $quoted_new__password = shell_quote $new__password; #old, wrong?
  $new_quoted_password = shell_quote $new__password; #new, better?
  $old_domain = $old->domain;
  $new_domain = $new->domain;

  #eventuall should check a "password-encoding" field
  if ( length($new->_password) == 13
       || $new->_password =~ /^\$(1|2a?)\$/ ) {
    $new_crypt_password = shell_quote $new->_password;
  } else {
    $new_crypt_password =
      crypt( $new->_password, $saltset[int(rand(64))].$saltset[int(rand(64))]
    );
  }

  if ( $self->option('usermod_pwonly') ) {
    my $error = '';
    if ( $old_username ne $new_username ) {
      $error ||= "can't change username";
    }
    if ( $old_domain ne $new_domain ) {
      $error ||= "can't change domain";
    }
    if ( $old_uid != $new_uid ) {
      $error ||= "can't change uid";
    }
    if ( $old_dir ne $new_dir ) {
      $error ||= "can't change dir";
    }
    return $error. ' ('. $self->exporttype. ' to '. $self->machine. ')'
      if $error;
  }
  $self->shellcommands_queue( $new->svcnum,
    user         => $self->option('user')||'root',
    host         => $self->machine,
    command      => eval(qq("$command")),
    stdin_string => eval(qq("$stdin")),
  );
}

#a good idea to queue anything that could fail or take any time
sub shellcommands_queue {
  my( $self, $svcnum ) = (shift, shift);
  my $queue = new FS::queue {
    'svcnum' => $svcnum,
    'job'    => "FS::part_export::shellcommands::ssh_cmd",
  };
  $queue->insert( @_ );
}

sub ssh_cmd { #subroutine, not method
  use Net::SSH '0.08';
  &Net::SSH::ssh_cmd( { @_ } );
}

#sub shellcommands_insert { #subroutine, not method
#}
#sub shellcommands_replace { #subroutine, not method
#}
#sub shellcommands_delete { #subroutine, not method
#}

