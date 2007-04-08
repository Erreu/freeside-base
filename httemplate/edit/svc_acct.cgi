%
%
%my $conf = new FS::Conf;
%my @shells = $conf->config('shells');
%
%my $curuser = $FS::CurrentUser::CurrentUser;
%
%my($svcnum, $pkgnum, $svcpart, $part_svc, $svc_acct, @groups);
%if ( $cgi->param('error') ) {
%
%  $svc_acct = new FS::svc_acct ( {
%    map { $_, scalar($cgi->param($_)) } fields('svc_acct')
%  } );
%  $svcnum = $svc_acct->svcnum;
%  $pkgnum = $cgi->param('pkgnum');
%  $svcpart = $cgi->param('svcpart');
%  $part_svc = qsearchs( 'part_svc', { 'svcpart' => $svcpart } );
%  die "No part_svc entry for svcpart $svcpart!" unless $part_svc;
%  @groups = $cgi->param('radius_usergroup');
%
%} elsif ( $cgi->param('pkgnum') && $cgi->param('svcpart') ) { #adding
%
%  $cgi->param('pkgnum') =~ /^(\d+)$/ or die 'unparsable pkgnum';
%  $pkgnum = $1;
%  $cgi->param('svcpart') =~ /^(\d+)$/ or die 'unparsable svcpart';
%  $svcpart = $1;
%
%  $part_svc=qsearchs('part_svc',{'svcpart'=>$svcpart});
%  die "No part_svc entry!" unless $part_svc;
%
%    $svc_acct = new FS::svc_acct({svcpart => $svcpart}); 
%
%    $svcnum='';
%
%} else { #editing
%
%  my($query) = $cgi->keywords;
%  $query =~ /^(\d+)$/ or die "unparsable svcnum";
%  $svcnum=$1;
%  $svc_acct=qsearchs('svc_acct',{'svcnum'=>$svcnum})
%    or die "Unknown (svc_acct) svcnum!";
%
%  my($cust_svc)=qsearchs('cust_svc',{'svcnum'=>$svcnum})
%    or die "Unknown (cust_svc) svcnum!";
%
%  $pkgnum=$cust_svc->pkgnum;
%  $svcpart=$cust_svc->svcpart;
%
%  $part_svc = qsearchs( 'part_svc', { 'svcpart' => $svcpart } );
%  die "No part_svc entry for svcpart $svcpart!" unless $part_svc;
%
%  @groups = $svc_acct->radius_groups;
%
%}
%
%my( $cust_pkg, $cust_main ) = ( '', '' );
%if ( $pkgnum ) {
%  $cust_pkg = qsearchs('cust_pkg', { 'pkgnum' => $pkgnum } );
%  $cust_main = $cust_pkg->cust_main;
%}
%
%unless ( $svcnum || $cgi->param('error') ) { #adding
%
%  #set gecos
%  if ($cust_main) {
%    unless ( $part_svc->part_svc_column('uid')->columnflag eq 'F' ) {
%      $svc_acct->setfield('finger',
%        $cust_main->getfield('first') . " " . $cust_main->getfield('last')
%      );
%    }
%  }
%
%  $svc_acct->set_default_and_fixed( {
%    #false laziness w/svc-acct::_fieldhandlers
%    'usergroup' => sub { 
%                         my( $self, $groups ) = @_;
%                         if ( ref($groups) eq 'ARRAY' ) {
%                           @groups = @$groups;
%                           $groups;
%                         } elsif ( length($groups) ) {
%                           @groups = split(/\s*,\s*/, $groups);
%                           [ @groups ];
%                         } else {
%                           @groups = ();
%                           [];
%                         }
%                       }
%  } );
%
%}
%
%#fixed radius groups always override & display
%if ( $part_svc->part_svc_column('usergroup')->columnflag eq 'F' ) {
%  @groups = split(',', $part_svc->part_svc_column('usergroup')->columnvalue);
%}
%
%my $action = $svcnum ? 'Edit' : 'Add';
%
%my $svc = $part_svc->getfield('svc');
%
%my $otaker = getotaker;
%
%my $username = $svc_acct->username;
%my $password;
%if ( $svc_acct->_password ) {
%  if ( $conf->exists('showpasswords') || ! $svcnum ) {
%    $password = $svc_acct->_password;
%  } else {
%    $password = "*HIDDEN*";
%  }
%} else {
%  $password = '';
%}
%
%my $ulen = 
%  $conf->exists('usernamemax')
%  ? $conf->config('usernamemax')
%  : dbdef->table('svc_acct')->column('username')->length;
%my $ulen2 = $ulen+2;
%
%my $pmax = $conf->config('passwordmax') || 8;
%my $pmax2 = $pmax+2;
%
%my $p1 = popurl(1);
%
%


<% include("/elements/header.html","$action $svc account") %>
% if ( $cgi->param('error') ) { 

  <FONT SIZE="+1" COLOR="#ff0000">Error: <% $cgi->param('error') %></FONT>
  <BR><BR>
% } 
% if ( $cust_main ) { 

  <% include( '/elements/small_custview.html', $cust_main, '', 1,
              popurl(2) . "view/cust_main.cgi") %>
  <BR>
% } 


<FORM NAME="OneTrueForm" ACTION="<% $p1 %>process/svc_acct.cgi" METHOD=POST>
<INPUT TYPE="hidden" NAME="svcnum" VALUE="<% $svcnum %>">
<INPUT TYPE="hidden" NAME="pkgnum" VALUE="<% $pkgnum %>">
<INPUT TYPE="hidden" NAME="svcpart" VALUE="<% $svcpart %>">

Service # <% $svcnum ? "<B>$svcnum</B>" : " (NEW)" %><BR>

<% ntable("#cccccc",2) %>

<TR>
  <TD ALIGN="right">Service</TD>
  <TD BGCOLOR="#eeeeee"><% $part_svc->svc %></TD>
</TR>

<TR>
  <TD ALIGN="right">Username</TD>
  <TD>
    <INPUT TYPE="text" NAME="username" VALUE="<% $username %>" SIZE=<% $ulen2 %> MAXLENGTH=<% $ulen %>>
  </TD>
</TR>

<TR>
  <TD ALIGN="right">Password</TD>
  <TD>
    <INPUT TYPE="text" NAME="_password" VALUE="<% $password %>" SIZE=<% $pmax2 %> MAXLENGTH=<% $pmax %>>
    (blank to generate)
  </TD>
</TR>
%
%my $sec_phrase = $svc_acct->sec_phrase;
%if ( $conf->exists('security_phrase') ) {
%


  <TR>
    <TD ALIGN="right">Security phrase</TD>
    <TD>
      <INPUT TYPE="text" NAME="sec_phrase" VALUE="<% $sec_phrase %>" SIZE=32>
      (for forgotten passwords)
    </TD>
  </TD>
% } else { 


  <INPUT TYPE="hidden" NAME="sec_phrase" VALUE="<% $sec_phrase %>">
% } 
%
%#domain
%my $domsvc = $svc_acct->domsvc || 0;
%if ( $part_svc->part_svc_column('domsvc')->columnflag eq 'F' ) {
%


  <INPUT TYPE="hidden" NAME="domsvc" VALUE="<% $domsvc %>">
% } else { 
%
%  my %svc_domain = ();
%
%  if ( $domsvc ) {
%    my $svc_domain = qsearchs('svc_domain', { 'svcnum' => $domsvc, } );
%    if ( $svc_domain ) {
%      $svc_domain{$svc_domain->svcnum} = $svc_domain;
%    } else {
%      warn "unknown svc_domain.svcnum for svc_acct.domsvc: $domsvc";
%    }
%  }
%
%  if ( $part_svc->part_svc_column('domsvc')->columnflag eq 'D' ) {
%    my $svc_domain = qsearchs('svc_domain', {
%      'svcnum' => $part_svc->part_svc_column('domsvc')->columnvalue,
%    } );
%    if ( $svc_domain ) {
%      $svc_domain{$svc_domain->svcnum} = $svc_domain;
%    } else {
%      warn "unknown svc_domain.svcnum for part_svc_column domsvc: ".
%           $part_svc->part_svc_column('domsvc')->columnvalue;
%    }
%  }
%
%  if ( $part_svc->part_svc_column('domsvc')->columnflag eq 'S' ) {
%    foreach my $domain
%              (split(',',$part_svc->part_svc_column('domsvc')->columnvalue)) {
%      my $svc_domain =
%        qsearchs('svc_domain', { 'svcnum' => $domain } );
%     $svc_domain{$svc_domain->svcnum} = $svc_domain if $svc_domain;
%    }
%  }elsif ($cust_pkg && !$conf->exists('svc_acct-alldomains') ) {
%    my @cust_svc =
%      map { qsearch('cust_svc', { 'pkgnum' => $_->pkgnum } ) }
%          qsearch('cust_pkg', { 'custnum' => $cust_pkg->custnum } );
%    foreach my $cust_svc ( @cust_svc ) {
%      my $svc_domain =
%        qsearchs('svc_domain', { 'svcnum' => $cust_svc->svcnum } );
%     $svc_domain{$svc_domain->svcnum} = $svc_domain if $svc_domain;
%    }
%  } else {
%    %svc_domain = map { $_->svcnum => $_ } qsearch('svc_domain', {} );
%  }
%
%


  <TR>
    <TD ALIGN="right">Domain</TD>
    <TD>
      <SELECT NAME="domsvc" SIZE=1>
% foreach my $svcnum (
%             sort { $svc_domain{$a}->domain cmp $svc_domain{$b}->domain }
%                  keys %svc_domain
%           ) {
%             my $svc_domain = $svc_domain{$svcnum};
%        


             <OPTION VALUE="<% $svc_domain->svcnum %>" <% $svc_domain->svcnum == $domsvc ? ' SELECTED' : '' %>><% $svc_domain->domain %>
% } 

      </SELECT>
    </TD>
  </TR>
% } 
%
%#pop
%my $popnum = $svc_acct->popnum || 0;
%if ( $part_svc->part_svc_column('popnum')->columnflag eq 'F' ) {
%


  <INPUT TYPE="hidden" NAME="popnum" VALUE="<% $popnum %>">
% } else { 


  <TR>
    <TD ALIGN="right">Access number</TD>
    <TD><% FS::svc_acct_pop::popselector($popnum) %></TD>
  </TR>
% } 
% #uid/gid 
% foreach my $xid (qw( uid gid )) { 
%
%  if ( $part_svc->part_svc_column($xid)->columnflag =~ /^[FA]$/
%       || ! $conf->exists("svc_acct-edit_$xid")
%     ) {
%  
% if ( length($svc_acct->$xid()) ) { 

  
      <TR>
        <TD ALIGN="right"><% uc($xid) %></TD>
          <TD BGCOLOR="#eeeeee"><% $svc_acct->$xid() %></TD>
        <TD>
        </TD>
      </TR>
% } 

  
    <INPUT TYPE="hidden" NAME="<% $xid %>" VALUE="<% $svc_acct->$xid() %>">
% } else { 

  
    <TR>
      <TD ALIGN="right"><% uc($xid) %></TD>
      <TD>
        <INPUT TYPE="text" NAME="<% $xid %>" SIZE=8 MAXLENGTH=6 VALUE="<% $svc_acct->$xid() %>">
      </TD>
    </TR>
% } 
% } 
%
%#finger
%if ( $part_svc->part_svc_column('uid')->columnflag eq 'F'
%     && ! $svc_acct->finger ) { 
%


  <INPUT TYPE="hidden" NAME="finger" VALUE="">
% } else { 


  <TR>
    <TD ALIGN="right">GECOS</TD>
    <TD>
      <INPUT TYPE="text" NAME="finger" VALUE="<% $svc_acct->finger %>">
    </TD>
  </TR>
% } 



<INPUT TYPE="hidden" NAME="dir" VALUE="<% $svc_acct->dir %>">
%
%#shell
%my $shell = $svc_acct->shell;
%if ( $part_svc->part_svc_column('shell')->columnflag eq 'F'
%     || ( !$shell && $part_svc->part_svc_column('uid')->columnflag eq 'F' )
%   ) {
%


  <INPUT TYPE="hidden" NAME="shell" VALUE="<% $shell %>">
% } else { 


  <TR>
    <TD ALIGN="right">Shell</TD>
    <TD>
      <SELECT NAME="shell" SIZE=1>
%
%           my($etc_shell);
%           foreach $etc_shell (@shells) {
%        


          <OPTION<% $etc_shell eq $shell ? ' SELECTED' : '' %>><% $etc_shell %>
% } 


      </SELECT>
    </TD>
  </TR>
% } 
% if ( $part_svc->part_svc_column('quota')->columnflag eq 'F' ) { 


  <INPUT TYPE="hidden" NAME="quota" VALUE="<% $svc_acct->quota %>">
% } else { 


  <TR>
    <TD ALIGN="right">Quota:</TD>
    <TD><INPUT TYPE="text" NAME="quota" VALUE="<% $svc_acct->quota %>"></TD>
  </TR>
% } 
% if ( $part_svc->part_svc_column('slipip')->columnflag =~ /^[FA]$/ ) { 


  <INPUT TYPE="hidden" NAME="slipip" VALUE="<% $svc_acct->slipip %>">
% } else { 


  <TR>
    <TD ALIGN="right">IP</TD>
    <TD><INPUT TYPE="text" NAME="slipip" VALUE="<% $svc_acct->slipip %>"></TD>
  </TR>
% } 
%
% if ( $curuser->access_right('Edit usage') ) { 
%   my %label = ( seconds => 'Seconds',
%                 upbytes => 'Upload bytes',
%                 downbytes => 'Download bytes',
%                 totalbytes => 'Total bytes',
%               );
%   foreach my $uf (keys %label) {
%     my $tf = $uf . "_threshold";
%     if ( $svc_acct->$tf ne '' ) { 

  <TR>
    <TD ALIGN="right"><% $label{$uf} %> remaining</TD>
    <TD><INPUT TYPE="text" NAME="<% $uf %>" VALUE="<% $svc_acct->$uf %>"></TD>
  </TR>
  <TR>
    <TD ALIGN="right"><% $label{$uf} %> threshold</TD>
    <TD><INPUT TYPE="text" NAME="<% $tf %>" VALUE="<% $svc_acct->$tf %>">(blank or zero disables <% lc($label{$uf}) %> remaining)</TD>
  </TR>
%     } 
%   } 
% } 
%
%foreach my $r ( grep { /^r(adius|[cr])_/ } fields('svc_acct') ) {
%  $r =~ /^^r(adius|[cr])_(.+)$/ or next; #?
%  my $a = $2;
%
% if ( $part_svc->part_svc_column($r)->columnflag =~ /^[FA]$/ ) { 


    <INPUT TYPE="hidden" NAME="<% $r %>" VALUE="<% $svc_acct->getfield($r) %>">
% } else { 


    <TR>
      <TD ALIGN="right"><% $FS::raddb::attrib{$a} %></TD>
      <TD><INPUT TYPE="text" NAME="<% $r %>" VALUE="<% $svc_acct->getfield($r) %>"></TD>
    </TR>
% } 
% } 



<TR>
  <TD ALIGN="right">RADIUS groups</TD>
% if ( $part_svc->part_svc_column('usergroup')->columnflag eq 'F' ) { 


    <TD BGCOLOR="#eeeeee"><% join('<BR>', @groups) %></TD>
% } else { 


    <TD><% FS::svc_acct::radius_usergroup_selector( \@groups ) %></TD>
% } 


</TR>
% foreach my $field ($svc_acct->virtual_fields) { 
% # If the flag is X, it won't even show up in $svc_acct->virtual_fields. 
% if ( $part_svc->part_svc_column($field)->columnflag ne 'F' ) { 


    <% $svc_acct->pvf($field)->widget('HTML', 'edit', $svc_acct->getfield($field)) %>
% } 
% } 

  
</TABLE>
<BR>

<INPUT TYPE="submit" VALUE="Submit">

</FORM></BODY></HTML>
