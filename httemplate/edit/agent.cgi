<!-- mason kludge -->
<%

my $agent;
if ( $cgi->param('error') ) {
  $agent = new FS::agent ( {
    map { $_, scalar($cgi->param($_)) } fields('agent')
  } );
} elsif ( $cgi->keywords ) {
  my($query) = $cgi->keywords;
  $query =~ /^(\d+)$/;
  $agent = qsearchs( 'agent', { 'agentnum' => $1 } );
} else { #adding
  $agent = new FS::agent {};
}
my $action = $agent->agentnum ? 'Edit' : 'Add';
my $hashref = $agent->hashref;

%>

<%= header("$action Agent", menubar(
  'Main Menu' => $p,
  'View all agents' => $p. 'browse/agent.cgi',
)) %>

<% if ( $cgi->param('error') ) { %>
<FONT SIZE="+1" COLOR="#ff0000">Error: <%= $cgi->param('error') %></FONT>
<% } %>

<FORM ACTION="<%=popurl(1)%>process/agent.cgi" METHOD=POST>
<INPUT TYPE="hidden" NAME="agentnum" VALUE="<%= $hashref->{agentnum} %>">
Agent #<%= $hashref->{agentnum} ? $hashref->{agentnum} : "(NEW)" %>

<%= &ntable("#cccccc", 2, '') %>
<TR>
  <TH ALIGN="right">Agent</TH>
  <TD><INPUT TYPE="text" NAME="agent" SIZE=32 VALUE="<%= $hashref->{agent} %>"></TD>
</TR>
<TR>
  <TH ALIGN="right">Agent type</TH>
  <TD><SELECT NAME="typenum" SIZE=1>

<% foreach my $agent_type (qsearch('agent_type',{})) { %>
  <OPTION VALUE="<%= $agent_type->typenum %>"<%= ( $hashref->{typenum} && ( $hashref->{typenum} == $agent_type->typenum ) ) ? ' SELECTED' : '' %>>
  <%= $agent_type->getfield('typenum') %>: <%= $agent_type->getfield('atype') %>
<% } %>

</SELECT></TD>
</TR>
<% if ( dbdef->table('agent')->column('disabled') ) { %>
  <TR>
    <TD ALIGN="right">Disable</TD>
    <TD><INPUT TYPE="checkbox" NAME="disabled" VALUE="Y"<%= $hashref->{disabled} eq 'Y' ? ' CHECKED' : '' %>></TD>
  </TR>
<% } %>
<TR>
  <TD ALIGN="right"><!--Frequency--></TD>
  <TD><INPUT TYPE="hidden" NAME="freq" VALUE="<%= $hashref->{freq} %>"></TD>
</TR>
<TR>
  <TD ALIGN="right"><!--Program--></TD>
  <TD><INPUT TYPE="hidden" NAME="prog" VALUE="<%= $hashref->{prog} %>"></TD>
</TR>
<% if ( dbdef->table('agent')->column('username') ) { %>
  <TR>
    <TD ALIGN="right">Agent interface username</TD>
    <TD><INPUT TYPE="text" NAME="username" VALUE="<%= $hashref->{username} %>"></TD>
  </TR>
  <TR>
    <TD ALIGN="right">Agent interface password</TD>
    <TD><INPUT TYPE="text" NAME="_password" VALUE="<%= $hashref->{_password} %>"></TD>
  </TR>
<% } %>
</TABLE>

<BR><INPUT TYPE="submit" VALUE="<%= $hashref->{agentnum} ? "Apply changes" : "Add agent" %>">
    </FORM>
  </BODY>
</HTML>
