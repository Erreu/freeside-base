package FS::ClientAPI_XMLRPC;

=head1 NAME

FS::ClientAPI_XMLRPC - Freeside XMLRPC accessible self-service API, on the backend

=head1 SYNOPSIS

This module implements the self-service API offered by xmlrpc.cgi and friends,
but on a backend machine.

=head1 DESCRIPTION

Use this API to implement your own client "self-service" module vi XMLRPC.

Each routine described in L<FS::SelfService> is available vi XMLRPC as the
method FS.SelfService.XMLRPC.B<method>.  All values are passed to the
selfservice-server in a struct of strings.  The return values are in a
struct as strings, arrays, or structs as appropriate for the values
described in L<FS::SelfService>.

=head1 BUGS

=head1 SEE ALSO

L<FS::SelfService::XMLRPC>, L<FS::SelfService>

=cut

use strict;

use vars qw($DEBUG $AUTOLOAD);
use FS::ClientAPI;

$DEBUG = 0;
$FS::ClientAPI::DEBUG = $DEBUG;

sub AUTOLOAD {
  my $call = $AUTOLOAD;
  $call =~ s/^FS::(SelfService::|ClientAPI_)XMLRPC:://;

  warn "FS::ClientAPI_XMLRPC::AUTOLOAD $call\n" if $DEBUG;

  my $autoload = &ss2clientapi;

  if (exists($autoload->{$call})) {
    shift; #discard package name;
    #$call = "FS::SelfService::$call";
    #no strict 'refs';
    #&{$call}(@_);
    #FS::ClientAPI->dispatch($autoload->{$call}, @_);
    FS::ClientAPI->dispatch($autoload->{$call}, { @_ } );
  }else{
    die "No such procedure: $call";
  }
}

#terrible false laziness w/SelfService.pm
# - fix at build time, by including some file in both selfserv and backend libs?
# - or fix at runtime, by having selfservice client ask server for the list?
sub ss2clientapi {
  {
  'passwd'                    => 'passwd/passwd',
  'chfn'                      => 'passwd/passwd',
  'chsh'                      => 'passwd/passwd',
  'login_info'                => 'MyAccount/login_info',
  'login'                     => 'MyAccount/login',
  'logout'                    => 'MyAccount/logout',
  'customer_info'             => 'MyAccount/customer_info',
  'edit_info'                 => 'MyAccount/edit_info',     #add to ss cgi!
  'invoice'                   => 'MyAccount/invoice',
  'invoice_logo'              => 'MyAccount/invoice_logo',
  'list_invoices'             => 'MyAccount/list_invoices', #?
  'cancel'                    => 'MyAccount/cancel',        #add to ss cgi!
  'payment_info'              => 'MyAccount/payment_info',
  'payment_info_renew_info'   => 'MyAccount/payment_info_renew_info',
  'process_payment'           => 'MyAccount/process_payment',
  'process_payment_order_pkg' => 'MyAccount/process_payment_order_pkg',
  'process_payment_change_pkg' => 'MyAccount/process_payment_change_pkg',
  'process_payment_order_renew' => 'MyAccount/process_payment_order_renew',
  'process_prepay'            => 'MyAccount/process_prepay',
  'realtime_collect'          => 'MyAccount/realtime_collect',
  'list_pkgs'                 => 'MyAccount/list_pkgs',     #add to ss (added?)
  'list_svcs'                 => 'MyAccount/list_svcs',     #add to ss (added?)
  'list_svc_usage'            => 'MyAccount/list_svc_usage',   
  'list_cdr_usage'            => 'MyAccount/list_cdr_usage',   
  'list_support_usage'        => 'MyAccount/list_support_usage',   
  'order_pkg'                 => 'MyAccount/order_pkg',     #add to ss cgi!
  'change_pkg'                => 'MyAccount/change_pkg', 
  'order_recharge'            => 'MyAccount/order_recharge',
  'renew_info'                => 'MyAccount/renew_info',
  'order_renew'               => 'MyAccount/order_renew',
  'cancel_pkg'                => 'MyAccount/cancel_pkg',    #add to ss cgi!
  'suspend_pkg'               => 'MyAccount/suspend_pkg',   #add to ss cgi!
  'charge'                    => 'MyAccount/charge',        #?
  'part_svc_info'             => 'MyAccount/part_svc_info',
  'provision_acct'            => 'MyAccount/provision_acct',
  'provision_external'        => 'MyAccount/provision_external',
  'unprovision_svc'           => 'MyAccount/unprovision_svc',
  'myaccount_passwd'          => 'MyAccount/myaccount_passwd',
  'create_ticket'             => 'MyAccount/create_ticket',
  'signup_info'               => 'Signup/signup_info',
  'skin_info'                 => 'MyAccount/skin_info',
  'access_info'               => 'MyAccount/access_info',
  'domain_select_hash'        => 'Signup/domain_select_hash',  # expose?
  'new_customer'              => 'Signup/new_customer',
  'capture_payment'           => 'Signup/capture_payment',
  'clear_signup_cache'        => 'Signup/clear_cache',
  'new_agent'                 => 'Agent/new_agent',
  'agent_login'               => 'Agent/agent_login',
  'agent_logout'              => 'Agent/agent_logout',
  'agent_info'                => 'Agent/agent_info',
  'agent_list_customers'      => 'Agent/agent_list_customers',
  'mason_comp'                => 'MasonComponent/mason_comp',
  'call_time'                 => 'PrepaidPhone/call_time',
  'call_time_nanpa'           => 'PrepaidPhone/call_time_nanpa',
  'phonenum_balance'          => 'PrepaidPhone/phonenum_balance',
  'bulk_processrow'           => 'Bulk/processrow',
  'check_username'            => 'Bulk/check_username',
  #sg
  'ping'                      => 'SGNG/ping',
  'decompify_pkgs'            => 'SGNG/decompify_pkgs',
  'previous_payment_info'     => 'SGNG/previous_payment_info',
  'previous_payment_info_renew_info'
                              => 'SGNG/previous_payment_info_renew_info',
  'previous_process_payment'  => 'SGNG/previous_process_payment',
  'previous_process_payment_order_pkg'
                              => 'SGNG/previous_process_payment_order_pkg',
  'previous_process_payment_change_pkg'
                              => 'SGNG/previous_process_payment_change_pkg',
  'previous_process_payment_order_renew'
                              => 'SGNG/previous_process_payment_order_renew',
  };
}


#XXX submit patch to SOAP::Lite

use XMLRPC::Transport::HTTP;

package XMLRPC::Transport::HTTP::Server;

@XMLRPC::Transport::HTTP::Server::ISA = qw(SOAP::Transport::HTTP::Server);

sub initialize; *initialize = \&XMLRPC::Server::initialize;
sub make_fault; *make_fault = \&XMLRPC::Transport::HTTP::CGI::make_fault;
sub make_response; *make_response = \&XMLRPC::Transport::HTTP::CGI::make_response;

1;
