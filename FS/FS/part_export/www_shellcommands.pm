package FS::part_export::www_shellcommands;

use strict;
use vars qw(@ISA %info);
use Tie::IxHash;
use FS::part_export;

@ISA = qw(FS::part_export);

tie my %options, 'Tie::IxHash',
  'user' => { label=>'Remote username', default=>'root' },
  'useradd' => { label=>'Insert command',
                 default=>'mkdir /var/www/$zone; chown $username /var/www/$zone; ln -s /var/www/$zone $homedir/$zone',
               },
  'userdel'  => { label=>'Delete command',
                  default=>'[ -n &quot;$zone&quot; ] && rm -rf /var/www/$zone; rm $homedir/$zone',
                },
  'usermod'  => { label=>'Modify command',
                  default=>'[ -n &quot;$old_zone&quot; ] && rm $old_homedir/$old_zone; [ &quot;$old_zone&quot; != &quot;$new_zone&quot; -a -n &quot;$new_zone&quot; ] && mv /var/www/$old_zone /var/www/$new_zone; [ &quot;$old_username&quot; != &quot;$new_username&quot; ] && chown -R $new_username /var/www/$new_zone; ln -s /var/www/$new_zone $new_homedir/$new_zone',
                },
;

%info = (
  'svc'     => 'svc_www',
  'desc'    => 'Run remote commands via SSH, for virtual web sites.',
  'options' => \%options,
  'notes'   => <<'END'
Run remote commands via SSH, for virtual web sites.  You will need to
<a href="../docs/ssh.html">setup SSH for unattended operation</a>.
<BR><BR>Use these buttons for some useful presets:
<UL>
  <LI>
    <INPUT TYPE="button" VALUE="Maintain directories" onClick'
      this.form.user.value = "root";
      this.form.useradd.value = "mkdir /var/www/$zone; chown $username /var/www/$zone; ln -s /var/www/$zone $homedir/$zone";
      this.form.userdel.value = "[ -n &quot;$zone&quot; ] && rm -rf /var/www/$zone; rm $homedir/$zone";
      this.form.usermod.value = "[ -n &quot;$old_zone&quot; ] && rm $old_homedir/$old_zone; [ &quot;$old_zone&quot; != &quot;$new_zone&quot; -a -n &quot;$new_zone&quot; ] && mv /var/www/$old_zone /var/www/$new_zone; [ &quot;$old_username&quot; != &quot;$new_username&quot; ] && chown -R $new_username /var/www/$new_zone; ln -s /var/www/$new_zone $new_homedir/$new_zone";
    '>
  <LI>
    <INPUT TYPE="button" VALUE="ISPMan CLI" onClick'
      this.form.user.value = "root";
      this.form.useradd.value = "/usr/local/ispman/ispman.addvhost -d $domain $zone";
      this.form.userdel.value = "/usr/local/ispman/idpman.deletevhost -d $domain $zone";
      this.form.usermod.value = "";
    '>
</UL>
The following variables are available for interpolation (prefixed with
<code>new_</code> or <code>old_</code> for replace operations):
<UL>
  <LI><code>$zone</code> - fully-qualified zone of this virtual host
  <LI><code>$domain</code> - base domain
  <LI><code>$username</code>
  <LI><code>$homedir</code>
  <LI>All other fields in <a href="../docs/schema.html#svc_www">svc_www</a>
    are also available.
</UL>
END
);


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
  my ( $self, $action, $svc_www) = (shift, shift, shift);
  my $command = $self->option($action);

  #set variable for the command
  no strict 'vars';
  {
    no strict 'refs';
    ${$_} = $svc_www->getfield($_) foreach $svc_www->fields;
  }
  my $domain_record = $svc_www->domain_record; # or die ?
  my $zone = $domain_record->zone; # or die ?
  my $domain = $domain_record->svc_domain->domain;
  my $svc_acct = $svc_www->svc_acct; # or die ?
  my $username = $svc_acct->username;
  my $homedir = $svc_acct->dir; # or die ?

  #done setting variables for the command

  $self->shellcommands_queue( $svc_www->svcnum,
    user         => $self->option('user')||'root',
    host         => $self->machine,
    command      => eval(qq("$command")),
  );
}

sub _export_replace {
  my($self, $new, $old ) = (shift, shift, shift);
  my $command = $self->option('usermod');
  
  #set variable for the command
  no strict 'vars';
  {
    no strict 'refs';
    ${"old_$_"} = $old->getfield($_) foreach $old->fields;
    ${"new_$_"} = $new->getfield($_) foreach $new->fields;
  }
  my $old_domain_record = $old->domain_record; # or die ?
  my $old_zone = $old_domain_record->reczone; # or die ?
  my $old_domain = $old_domain_record->svc_domain->domain;
  $old_zone .= ".$old_domain" unless $old_zone =~ /\.$/;

  my $old_svc_acct = $old->svc_acct; # or die ?
  my $old_username = $old_svc_acct->username;
  my $old_homedir = $old_svc_acct->dir; # or die ?

  my $new_domain_record = $new->domain_record; # or die ?
  my $new_zone = $new_domain_record->reczone; # or die ?
  my $new_domain = $new_domain_record->svc_domain->domain;
  unless ( $new_zone =~ /\.$/ ) {
    my $new_svc_domain = $new_domain_record->svc_domain; # or die ?
    $new_zone .= '.'. $new_svc_domain->domain;
  }

  my $new_svc_acct = $new->svc_acct; # or die ?
  my $new_username = $new_svc_acct->username;
  my $new_homedir = $new_svc_acct->dir; # or die ?

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
    'job'    => "FS::part_export::www_shellcommands::ssh_cmd",
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

