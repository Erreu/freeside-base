package FS::ClientAPI::passwd;

use strict;
use FS::Record qw(qsearchs);
use FS::svc_acct;
use FS::svc_domain;

use FS::ClientAPI; #hmm
FS::ClientAPI->register_handlers(
  'passwd/passwd' => \&passwd,
  'passwd/chfn' => \&chfn,
  'passwd/chsh' => \&chsh,
);

sub passwd {
  my $packet = shift;

  my $domain = qsearchs('svc_domain', { 'domain' => $packet->{'domain'} } )
    or return { error => "Domain $domain not found" };

  my $old_password = $packet->{'old_password'};
  my $new_password = $packet->{'new_password'};
  my $new_gecos = $packet->{'new_gecos'};
  my $new_shell = $packet->{'new_shell'};

   #false laziness w/FS::ClientAPI::MyAccount::login
 
   my $svc_acct = qsearchs( 'svc_acct', { 'username'  => $packet->{'username'},
                                          'domsvc'    => $svc_domain->svcnum, }
                          );
   return { error => 'User not found.' } unless $svc_acct;
   return { error => 'Incorrect password.' }
     unless $svc_acct->check_password($old_password);

  my %hash = $svc_acct->hash;
  my $new_svc_acct = new FS::svc_acct ( \%hash );
  $new_svc_acct->setfield('_password', $new_password ) 
    if $new_password && $new_password ne $old_password;
  $new_svc_acct->setfield('finger',$new_gecos) if $new_gecos;
  $new_svc_acct->setfield('shell',$new_shell) if $new_shell;
  my $error = $new_svc_acct->replace($svc_acct);

  return { error => $error };

}

sub chfn {}

sub chsh {}

1;

