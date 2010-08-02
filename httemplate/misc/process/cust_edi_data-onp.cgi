%
%
%  my $fh = $cgi->upload('csvfile');
%  #warn $cgi;
%  #warn $fh;
%
%  my $error = defined($fh)
%    ? FS::cust_main::batch_edidata_onp( {
%        filehandle => $fh,
%        agentnum   => scalar($cgi->param('agentnum')),
%        refnum     => scalar($cgi->param('refnum')),
%        pkgpart    => scalar($cgi->param('pkgpart')),
%        #'fields'    => [qw( cust_pkg.setup dayphone first last address1 address2
%        #                   city state zip comments                          )],
%        'format'   => scalar($cgi->param('format')),
%      } )
%    : 'No file';
%
%  if ( $error =~ /ERROR/) {
%    

    <!-- mason kludge -->
%
%    eidiot($error);
%#    $cgi->param('error', $error);
%#    print $cgi->redirect( "${p}cust_main-import.cgi
%  } else {
%    
%# OK let define the heading
%
%# general customer info
%my @field_descriptions1 = ( '810/867 usage match','F. Name', 'L. Name', 'Cust. Num',
%                            'SVC Num', 'Balance', 'Last Billed','Last Read #', '');
%
%# info collected from 810 & 867 to be entered into usage_elec
%my @field_descriptions2 = ( 'Start Date',
%                            'End Date', 'Prev Read', 'Curr Read', 'TDSP',
%                            'Meter Mulx', '867 Usage', 'Measure Demand', 'Billed Demand',
%                            '','','','');
%
%# info from 810
%my @field_descriptions3 = ( 'Invc #', '', 'Trans #/867 ref#', 'ESIID', '', '',
%                            'TDSP','', 'Due Date', '', 'Received Date', '810 usage', '',
%                            'Start Date', 'End Date', 
%                            '', '', '', '', '??', 'Billed Demand', 'Measured Demand',
%                            '','','','','','');
%
%# info from 867
%my @field_descriptions4 = ( 'Prev_Read', 'Curr Read', 'Multiplier', 
%                            'Total Usage','');
%
%# info from excel formula
%my @field_descriptions5 = ( 'Total Usage Different 810&867' );
%
%my @p_fields = ( 'p_prev_date', 'p_curr_date', 'p_prev_reading', 
%                 'p_curr_reading', 'p_tdsp', 'p_meter_mult', 'p_total_usage', 
%                 'p_measured_demand', 'p_billed_demand', 'p_svcnum',
%                 'p_first', 'p_last', 'p_balance', 'p_last_billed');
%#                 'p_entry_date', 'p_meter_number');
%my @p_fields_associates_index = ( 9, 10, 11,
%                                  12, 28, 14, 15,
%                                  16, 17, 4,
%                                  1, 2, 5, 6); 
%
%#my $description = join(',',@field_descriptions);
%
%my @field_name = qw / prev_date curr_date prev_read curr_read tdsp
%                      meter_multiplier total_usage measured_demand
%                      billed_demand svcnum _date meter_number /;
%my $date_exception = '(prev_date|curr_date|_date)';
%my $p1 = popurl(0);

%  my @usage_data = split /\n/,$error;

%  #my @items = split /\n/,$error;
%  my (@usage_cvs, @table_item);
%  foreach my $cust_usage (@usage_data) {
%    my @usage_ele = split ',',$cust_usage;
%    my $svc_num = $usage_ele[4];
%    my $cust_last_name = $usage_ele[2];
%    my $cust_num = $usage_ele[3];
%
%    # first thing first, let add the last reading from usage elec into table
%    # get the previous 1 usage_elec items
%    my @usage_obj = FS::usage_elec::query_usage($svc_num, 1);
%    my $usage = pop @usage_obj;
%    $usage_ele[7] = $usage->curr_read if $usage; #only if usage exist
%
%    my $pass_str = '';
%    my $i=0;
%    foreach my $p_field (@p_fields) {
%      my $ele_index = $p_fields_associates_index[$i];
%      $i++;
%      if ($pass_str) {
%        $pass_str .= "\&${p_field}=" . $usage_ele[$ele_index];
%      }
%      else {
%        $pass_str = "${p_field}=" . $usage_ele[$ele_index];
%      }
%    }
%     
%    $usage_ele[2]="<A HREF=\"../../view/cust_main.cgi?${cust_num}\" target=\"_blank\">${cust_last_name}</A>";
%
%    $usage_ele[3]="<A HREF=\"../../edit/usage_elec_prefilled_input.cgi?${pass_str}\" target=\"_blank\">$cust_num</A>";

%    # insert TD tag
%    my $str = join("\n", map("<TD>" . $_ . "</TD>", @usage_ele));
%
%    # let figure out if this particular usage data has already been entered 
%    # into the usage_elec table
%    # if it has, highlight it so the user can identify it
%    # To check for this, we perform some quick check (prev_date, curr_date, 
%    # prev_reading, curr_reading, and total_usage)
%    my @exist_in_usage_elec; #identify usage exist in usage_elec table
%    my @usages_history = qsearch ( {
%                           'table'   => 'usage_elec',
%                           'hashref' => { 'op'  => '=',
%                                          'svcnum' => $svc_num
%                                        },
%                            # sort in DESCending order so it easier to splice
%                            # the array in the next step
%                           'extra_sql' => 'ORDER BY _date DESC'
%                          } );
%    #my $usage_history_no = scalar(@usages_history);
%    my (%h_prev_date, %h_curr_date, %h_prev_read, %h_curr_read, 
%        %h_total_usage);
%    foreach my $usage (@usages_history) {
%      $h_prev_date{$usage->prev_date} = 1;
%      $h_curr_date{$usage->curr_date} = 1;
%      $h_prev_read{$usage->prev_read} = 1;
%      $h_curr_read{$usage->curr_read} = 1;
%      $h_total_usage{$usage->total_usage} = 1;
%    }
%
%    if ( exists $h_prev_date{str2time($usage_ele[9])} &&
%         exists $h_curr_date{str2time($usage_ele[10])} &&
%         exists $h_prev_read{$usage_ele[11]} &&
%         exists $h_curr_read{$usage_ele[12]} &&
%         exists $h_total_usage{$usage_ele[15]} ) {
%      # when data already entered into usage_elec
%      $str =  "<tr bgcolor=\"#9999ff\">$str</tr>";
%
%    }
%    else {
%      $str = "<tr>$str</tr>";
%    }
%
%    push(@table_item,$str);
%    push(@usage_cvs,join(',',@usage_ele)); #for exporting csv purposes
%  }
%
%  my $str_cvs = join "<BR>",@usage_cvs; #for exporting csv purposes
%  #print $str_cvs;
    <!-- mason kludge -->
    <% include("/elements/header.html","Import successful") %> 
<table border="2" frame="border" rules="all">
%
% # print the heading
% print "<tr class='maintitle'>"
%  . join("\n", map("<th bgcolor=\"#88b2ce\">" . $_ . "</th>", @field_descriptions1))
%  . join("\n", map("<th bgcolor=\"#ffff99\">" . $_ . "</th>", @field_descriptions2))
%  . join("\n", map("<th bgcolor=\"#ff9999\">" . $_ . "</th>", @field_descriptions3))
%  . join("\n", map("<th bgcolor=\"#66cc00\">" . $_ . "</th>", @field_descriptions4))
%  . join("\n", map("<th bgcolor=\"#ff99cc\">" . $_ . "</th>", @field_descriptions5))
%  . "</tr>\n";
%
% # print the table
% foreach my $e (@table_item) {
%   #print "<TR>$e</TR>";
%   print $e;
% }
</table>
%
% # dumping CSV data out 
% #foreach my $cvs_item (@usage_cvs) {
% #  print "$cvs_item<BR>";
% #}
    
%
%  }
%

