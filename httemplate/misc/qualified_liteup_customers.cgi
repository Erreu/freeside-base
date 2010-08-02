<% include("/elements/header.html",'LITEUP') %>

<h3> <FONT COLOR="Blue">Process new Liteup List</FONT></h3>
<FORM ACTION="process/qualified_liteup_customers.cgi" METHOD="post" ENCTYPE="multipart/form-data">

Import a text file from PUCT containg qualified LITEUP customers.
<BR>
The text file should contain ESIID, Address, City, StateZip, Qualifydate.  All seperated by 2 or more white spaces.  
<BR><BR>
ie.
<BR>
10032789488231455        3608 ORING         EDINBURG  TX78539   2008030120080731<BR>
1008939284701838499830   2206 W REEN RD     HOUSTON   TX77067   2008030120080731
<BR><BR>

<% &ntable("#cccccc") %>

<% include('/elements/tr-select-agent.html', '', #$agentnum,
              'label'       => "<B>Agent</B>",
              'empty_label' => 'Select agent',
           )
%>

<!--
<TR>
  <TH ALIGN="right">Format</TH>
  <TD>
    <SELECT NAME="format">
      <OPTION VALUE="simple">Simple
      <OPTION VALUE="extended" SELECTED>Extended
    </SELECT>
  </TD>
</TR>
-->

<TR>
  <TH ALIGN="right">filename</TH>
  <TD><INPUT TYPE="file" NAME="textfile"></TD>
</TR>
% #include('/elements/tr-select-part_referral.html')
%

</TABLE>
<BR>

<INPUT STYLE="background-color:lightgreen" TYPE="submit" name="action" VALUE="Process List">

<BR><BR>
<hr color="#CC2277" size="5">

<h3> <FONT COLOR="Blue">Audit Liteup Program</FONT></h3>

<TABLE>
<% include( '/elements/tr-input-beginning_ending.html' ) %>
</TABLE>

<BR>
<INPUT STYLE="background-color:lightgreen" TYPE="submit" name="action" VALUE="Get Report">

<BR><BR>
<hr color="#CC2277" size="5">

</FORM>

<% include('/elements/footer.html') %>

<%once>
my $req = qq!<font color="#ff0000">*</font>!;
</%once>


