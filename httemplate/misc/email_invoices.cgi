<%

my $server = new FS::UI::Web::JSRPC 'FS::cust_bill::process_reemail';
$server->process;

%>
