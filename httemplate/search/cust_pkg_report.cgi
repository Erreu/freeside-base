<HTML>
  <HEAD>
    <TITLE>Packages</TITLE>
    <LINK REL="stylesheet" TYPE="text/css" HREF="../elements/calendar-win2k-2.css" TITLE="win2k-2">
    <SCRIPT TYPE="text/javascript" SRC="../elements/calendar_stripped.js"></SCRIPT>
    <SCRIPT TYPE="text/javascript" SRC="../elements/calendar-en.js"></SCRIPT>
    <SCRIPT TYPE="text/javascript" SRC="../elements/calendar-setup.js"></SCRIPT>
  </HEAD>
  <BODY BGCOLOR="#e8e8e8">
    <H1>Packages</H1>
    <FORM ACTION="cust_pkg.cgi" METHOD="GET">
    <INPUT TYPE="hidden" NAME="magic" VALUE="bill">
      Return packages with next bill date:<BR><BR>
      <TABLE>
        <TR>
          <TD ALIGN="right">From: </TD>
          <TD><INPUT TYPE="text" NAME="beginning" ID="beginning_text" VALUE="" SIZE=11 MAXLENGTH=10> <IMG SRC="../images/calendar.png" ID="beginning_button" STYLE="cursor: pointer" TITLE="Select date"><BR><I>m/d/y</I></TD>
<SCRIPT TYPE="text/javascript">
  Calendar.setup({
    inputField: "beginning_text",
    ifFormat:   "%m/%d/%Y",
    button:     "beginning_button",
    align:      "BR"
  });
</SCRIPT>
        </TR>
        <TR>
          <TD ALIGN="right">To: </TD>
          <TD><INPUT TYPE="text" NAME="ending" ID="ending_text" VALUE="" SIZE=11 MAXLENGTH=10> <IMG SRC="../images/calendar.png" ID="ending_button" STYLE="cursor: pointer" TITLE="Select date"><BR><I>m/d/y</I></TD>
<SCRIPT TYPE="text/javascript">
  Calendar.setup({
    inputField: "ending_text",
    ifFormat:   "%m/%d/%Y",
    button:     "ending_button",
    align:      "BR"
  });
</SCRIPT>
        </TR>
<% my %agent_search = dbdef->table('agent')->column('disabled')
                        ? ( 'disabled' => '' ) : ();
   my @agents = qsearch( 'agent', \%agent_search );
   if ( scalar(@agents) == 1 ) {
%>
     <INPUT TYPE="hidden" NAME="agentnum" VALUE="<%= $agents[0]->agentnum %>">
<% } else { %>

        <TR>
          <TD ALIGN="right">Agent: </TD>
          <TD><SELECT NAME="agentnum"><OPTION VALUE="">(all)
          <% foreach my $agent ( sort { $a->agent cmp $b->agent; } @agents) { %>
            <OPTION VALUE="<%= $agent->agentnum %>"><%= $agent->agent %>
          <% } %>
          </TD>
        </TR>
<% } %>
      </TABLE>
      <BR><INPUT TYPE="submit" VALUE="Get Report">

    </FORM>

  </BODY>
</HTML>

