%my $debug=0; # toggle debug
%my( $svcnum,  $pkgnum, $svcpart, $part_svc, $svc_external );
%my @field_descriptions = ( 'prev date', 'curr date', 'prev reading',
%                           'curr reading', 'tdsp', 'meter mult',
%                           'total usage', 'measured demand', 'billed demand',
%                           'svcnum', 'entry date', 'meter number' );
%my @field_name = qw / prev_date curr_date prev_read curr_read tdsp 
%                      meter_multiplier total_usage measured_demand
%                      billed_demand svcnum _date meter_number /;
%my $date_exception = '(prev_date|curr_date|_date)';
%
%if ( $cgi->param('error') ) {
%  ### handle error call
%  $svcnum = $cgi->param('svcnum');
%}
%else {
%
%  my($query) = $cgi->keywords;
%  $query =~ /^(\d+)$/ or die "unparsable svcnum";
%  $svcnum=$1;
%
%}
%
%# this is sample data for print in case no previous record of usage_elec
%my @sample_data = ( '20070201', '20070228', '10000', '100100', '76.50',
%                    '5', '500', '179', '220', "$svcnum", 'NA', '030234972LM');
%
%### this is where i start
%### 
%### let gather all the info from usage_elec for the particular 'svcnum'
%###
%my $p1 = popurl(1);
%
%print qq!<FONT SIZE="+1" COLOR="#ff0000">Error: !, $cgi->param('error'),
%      "</FONT>"
%  if $cgi->param('error');
%
%print qq!<FORM ACTION="${p1}process/usage_elec_manual_input.cgi" METHOD=POST>!;
%
%# print header
%print header("Manually Adding Record to usage_elec Table", '');
%
%#display
%#
%#
<TABLE BORDER=1>
% 
% # -ctran 04/10/08
% # change getting previous 10 record to 13 so we can see at least 1 year 
% # worth of transaction
% # get the previous 13 usage_elec items
% my @usage_obj = FS::usage_elec::query_usage($svcnum, 13); 
%
% # print the heading
% print "<TR bgcolor=#88b2ce class='maintitle'>"
%      . join("\n", map("<TH>" . $_ . "</TH>", @field_descriptions))
%      . "</TR>\n";
%
% if (@usage_obj) {
%   foreach my $usage (@usage_obj) {
%     # fill @usage_ele with data order by @field_name
%     my @usage_ele = ();
%     foreach my $field (@field_name) {
%       if ( $field =~ /$date_exception/ ) {
%         # exception handling of converting time to string
%         push(@usage_ele,time2str("%Y%m%d",$usage->$field));
%       }
%       else {
%#debug: field= <% $field %> = <% $usage->$field %><BR>
%         push(@usage_ele, $usage->$field); 
%       }
%     }
%
%     print "<TR bgcolor=#e8e8ea class='mainbody'>" 
%          . join("\n", map("<TD>" . $_ . "</TD>", @usage_ele))
%          . "</TR>\n";
%   } 
% }
%
% ###
% ### gathering pre-filled information
% ###
%
% my ($h_prev_date, $h_prev_read, $h_tdsp, $h_meter_multiplier,
%     $h_measured_demand, $h_billed_demand, $h_svcnum, $h_meter_number);
%
% if (@usage_obj) {
%  # fill in all the history data
%  my $lindex = $#usage_obj;
%  $h_prev_date = time2str("%Y%m%d",$usage_obj[$lindex]->curr_date);
%  $h_prev_read = $usage_obj[$lindex]->curr_read;
%  $h_tdsp = $usage_obj[$lindex]->tdsp;
%  $h_meter_multiplier = $usage_obj[$lindex]->meter_multiplier;
%  $h_measured_demand = $usage_obj[$lindex]->measured_demand;
%  $h_billed_demand = $usage_obj[$lindex]->billed_demand;
%  $h_svcnum = $usage_obj[$lindex]->svcnum;
%  $h_meter_number = $usage_obj[$lindex]->meter_number;
% }
% 
% # this hash store info to configure the table with text box for input
% # size - [int] how big textbox
% # value - [alpha numeric] default value of the text box
% # extra - [alpha numeric] other option for text box.  I.E. READONLY
% #         mean the text box is a readonly
% my %field_info = (
%                   prev_date => {
%                                  'size'     => '8', 
%                                  'value'    => $h_prev_date, 
%                                },
%                   curr_date => { 'size'     => '8' },
%                   prev_read => {
%                                  'size'     => '8', 
%                                  'value'    => $h_prev_read, 
%                                },
%                   curr_read => { 'size'     => '8' },
%                   tdsp      => {
%                                  'size'     => '8', 
%                                  'value'    => $h_tdsp,
%                                },
%                   meter_multiplier => {
%                                  'size'  => '4', 
%                                  'value' => $h_meter_multiplier,
%                                       },
%                   total_usage => { 'size'     => '6' },
%                   measured_demand => {
%                                  'size'  => '4', 
%                                  'value' => $h_measured_demand,
%                                      },
%                   billed_demand => {
%                                  'size'  => '4', 
%                                  'value' => $h_billed_demand,
%                                    },
%                   svcnum => {
%                               'size'     => '6', 
%                               'value'    => $svcnum,
%                               'extra'    => 'READONLY'
%                             },
%                   _date => {
%                              'size'     => '8', 
%                              'value'    => 'N/A',
%                              'extra'    => 'READONLY'
%                             },
%                   meter_number => {
%                              'size'     => '14', 
%                              'value'    => $h_meter_number,
%                                   },
%                 );
%
%
% # input box for entry
% print qq !<TR bgcolor=#e8e8ea class='mainbody'>!; 
% my $input_style = 'STYLE="color:#000000; background-color: #FFFFCC;"';
% foreach my $field (@field_name) {
%   my $txt = '';
%   $txt .= ' SIZE=' . $field_info{$field}->{'size'} 
%                                   if (exists($field_info{$field}->{'size'}));
%   $txt .= ' VALUE="' . $field_info{$field}->{'value'} . '"' 
%                                   if (exists($field_info{$field}->{'value'}));
%   $txt .= ' ' . $field_info{$field}->{'extra'} 
%                                   if (exists($field_info{$field}->{'extra'}));
%   if ($field eq 'meter_multiplier') {
%     print qq !
%               <TD>
%                <TABLE>
%                 <TD>
%                   <INPUT TYPE="text" $input_style NAME="$field" $txt>
%                 </TD>
%                 <TD>
%                   <INPUT TYPE="checkbox" NAME="ignore_meter_multiplier">Ignore<P>
%                 </TD>
%                </TABLE>
%               </TD>
%              !;
%   }
%   else {
%     print qq !
%               <TD>
%               <INPUT TYPE="text" $input_style NAME="$field" $txt>
%               </TD>
%              !;
%  }
% } 
% print "</TR>\n";
% 

</TABLE><BR>
%print "<BR>measured demand = ",$h_measured_demand,"\n<BR>" if ($debug);
%
<INPUT TYPE="submit" VALUE="Submit">
<INPUT TYPE="Reset" VALUE="Clear">
<INPUT TYPE=BUTTON OnClick="$cgi->redirect(popurl(2)."view/svc_external.cgi?$svcnum")"
       VALUE="Cancel">
%
% print qq !
%   <br><br>
%   prev_date, curr_date -
%               8 digit in format of yyyymmdd (y-year m-month d-date)<br>
%   prev_read, curr_read - positive interger. Also, curr_read > prev_read
%                          Unless meter multiplier ignore value is set.  In
%                          this case, this condition will be ignore.<br>
%   tdsp - an dollar amount w/wo cent<br>
%   meter_multiplier - positive integer<br>
%   total_usage -
%           should equal (total_usage = (prev_read-curr_read) * meter_multiplier)
%           unless meter multiplier ignore value is set<br>
%   measured_demand - positive integer<br>
%   billed_demand - positive integer<br>
% !;
%
    </FORM>
  </BODY>
</HTML>

