<%= header('Address Blocks', menubar('Main Menu'   => $p)) %>
<%

use NetAddr::IP;

my @addr_block = qsearch('addr_block', {});
my @router = qsearch('router', {});
my $block;
my $p2 = popurl(2);
my $path = $p2 . "edit/process/addr_block";

%>

<% if ($cgi->param('error')) { %>
   <FONT SIZE="+1" COLOR="#ff0000">Error: <%=$cgi->param('error')%></FONT>
   <BR><BR>
<% } %>

<%=table()%>

<% foreach $block (sort {$a->NetAddr cmp $b->NetAddr} @addr_block) { %>
  <TR>
    <TD><%=$block->NetAddr%></TD>
  <% if (my $router = $block->router) { %>
    <% if (scalar($block->svc_broadband) == 0) { %>
    <TD>
      <%=$router->routername%>
    </TD>
    <TD>
      <FORM ACTION="<%=$path%>/deallocate.cgi" METHOD="POST">
        <INPUT TYPE="hidden" NAME="blocknum" VALUE="<%=$block->blocknum%>">
        <INPUT TYPE="submit" NAME="submit" VALUE="Deallocate">
      </FORM>
    </TD>
    <% } else { %>
    <TD COLSPAN="2">
    <%=$router->routername%>
    </TD>
    <% } %>
  <% } else { %>
    <TD>
      <FORM ACTION="<%=$path%>/allocate.cgi" METHOD="POST">
        <INPUT TYPE="hidden" NAME="blocknum" VALUE="<%=$block->blocknum%>">
        <SELECT NAME="routernum" SIZE="1">
    <% foreach (@router) { %>
          <OPTION VALUE="<%=$_->routernum %>"><%=$_->routername%></OPTION>
    <% } %>
        </SELECT>
        <INPUT TYPE="submit" NAME="submit" VALUE="Allocate">
      </FORM>
    </TD>
    <TD>
      <FORM ACTION="<%=$path%>/split.cgi" METHOD="POST">
        <INPUT TYPE="hidden" NAME="blocknum" VALUE="<%=$block->blocknum%>">
        <INPUT TYPE="submit" NAME="submit" VALUE="Split">
      </FORM>
    </TD>
  </TR>
<% }
 } %>
  <TR><TD COLSPAN="3"><BR></TD></TR>
  <TR>
    <FORM ACTION="<%=$path%>/add.cgi" METHOD="POST">
    <TD>Gateway/Netmask</TD>
    <TD>
      <INPUT TYPE="text" NAME="ip_gateway" SIZE="15">/<INPUT TYPE="text" NAME="ip_netmask" SIZE="2">
    </TD>
    <TD>
      <INPUT TYPE="submit" NAME="submit" VALUE="Add">
    </TD>
    </FORM>
  </TR>
</TABLE>
</BODY>
</HTML>

