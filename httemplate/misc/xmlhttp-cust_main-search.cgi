% if ( $sub eq 'custnum_search' ) {
% 
%   my $custnum = $cgi->param('arg');
%   my $cust_main = qsearchs({
%     'table'   => 'cust_main',
%     'hashref' => { 'custnum' => $custnum },
%     'extra_sql' => ' AND '. $FS::CurrentUser::CurrentUser->agentnums_sql,
%   });
%     
"<% $cust_main ? $cust_main->name : '' %>"
%
% } elsif ( $sub eq 'smart_search' ) {
%
%   my $string = $cgi->param('arg');
%   my @cust_main = smart_search( 'search' => $string );
%   my $return = [ map [ $_->custnum, $_->name ], @cust_main ];
%     
<% objToJson($return) %>
% } 
<%init>

my $sub = $cgi->param('sub');

</%init>
