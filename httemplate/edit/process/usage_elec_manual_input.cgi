%
%$cgi->param('svcnum') =~ /^(\d*)$/ or die "Illegal svcnum!";
%my $svcnum =$1;
%$svcnum = $cgi->param('svcnum');
svcnum = <% $svcnum %><br>
%
%my $old = qsearchs('svc_external',{'svcnum'=>$svcnum}) if $svcnum;
%
%
%### this is the field name for usage_elec with the exception of
%### prev_date, curr_date, _date
%my @field_name = qw / prev_read curr_read tdsp
%                      meter_multiplier total_usage measured_demand
%                      billed_demand svcnum meter_number /;
%my ($prev_date, $curr_date, $_date);
%
%my %usage_hash = (
%                   map {
%                        ($_, scalar($cgi->param($_)))
%                       } ( @field_name )
%                 );
%
% my $error = '';
%
% # Some general rules regarding the data
% # prev_date, curr_date - 
% #             8 digit in format of yyyymmdd (y-year m-month d-date)
% # prev_read, curr_read - positive interger. curr_read > prev_read
% # tdsp - an dollar amount w/wo cent
% # meter_multiplier - positive integer
% # total_usage - 
% #         should equal (total_usage = (prev_read-curr_read) * meter_multiplier
% #         unless meter multiplier ignore value is set
% # measured_demand - positive integer
% # billed_demand - positive integer
% # meter_number - alpha numeric value
%
% # prev_date, curr_date - 
% #             8 digit in format of yyyymmdd (y-year m-month d-date)
% my ($pd, $cd) = ($cgi->param('prev_date'),$cgi->param('curr_date'));
% if ( $pd =~ /^(\d{4})(\d{2})(\d{2})$/ ) {
%   my ($y,$m,$d) = ($1,$2,$3);
%   if ($m < 01 || $m > 12 || $d < 01 || $d > 31) {
%     $error = "error: previous date '$pd' must follow the rule"
%             ." of being 8 digit in format of yyyymmdd (y-year m-month d-date)";
%     $cgi->param('error', $error);
%     print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
%   }
% }
% else {
%   $error = "error: previous date '$pd' must follow the rule"
%           ." of being 8 digit in format of yyyymmdd (y-year m-month d-date)";
%   $cgi->param('error', $error);
%   print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
% if ( ($cd =~ /^(\d{4})(\d{2})(\d{2})$/) ) {
%   my ($y,$m,$d) = ($1,$2,$3);
%   if ($m < 01 || $m > 12 || $d < 01 || $d > 31) {
%     $error = "error: previous date '$cd' must follow the rule"
%             ." of being 8 digit in format of yyyymmdd (y-year m-month d-date)";
%     $cgi->param('error', $error);
%     print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
%   }
% }
% else {
%   $error = "error: previous date '$cd' must follow the rule"
%           ." of being 8 digit in format of yyyymmdd (y-year m-month d-date)";
%   $cgi->param('error', $error);
%   print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
%
% my $multiplier_ignore_flag = $cgi->param('ignore_meter_multiplier');
%
% # check prev_read and curr_read
% my ($pr, $cr) = ($usage_hash{'prev_read'},$usage_hash{'curr_read'});
% if ($pr =~ /^\d+$/ && $cr =~ /^\d+$/) {
%   # prev and curr are integer
%   if ( ($pr > $cr) && (!$multiplier_ignore_flag) ) {
%     # prev > current .. this is not possible unless meter change
%     $error = "error: previous reading '$pr' is greater than current reading"
%             ." '$cr'\n";
%     $cgi->param('error', $error);
%     print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
%   }
% }
% else {
%  $error = "error: previous reading '$pr' or current reading '$cr'"
%          ." need to follow the simple rule of being a positive integer.\n";
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
% # tdsp - an dollar amount w/wo cent
% my $tdsp = $usage_hash{'tdsp'};
% if ( $tdsp !~ /^(\d+|\d+\.\d{2})$/ ) {
%   $error = "error: tdsp '$tdsp' must follow the rule<br>"
%          ." of being a dollar amount w/wo cent value.<br>";
%   $cgi->param('error', $error);
%   print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
% # meter_multiplier - positive integer
% my $mm = $usage_hash{'meter_multiplier'};
% #if ( ($mm < 0) || ($mm !~ /^\d+$/) ) {
% if ( ($mm < 0) || ($mm !~ /^\d+\.{0,1}\d*$/) ) {
%   $error = "error: meter multiplier '$mm' must follow the rule<br>"
%          ." of being a positive integer.<br>";
%   $cgi->param('error', $error);
%   print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
% # total_usage - 
% #         should equal (total_usage = (curr_read-prev_read) * meter_multiplier
% #         unless meter multiplier ignore value is set
% my $input_tu = $usage_hash{'total_usage'};
% my $tu = ($cr-$pr)*$mm;
% if ( ( ($tu != $input_tu) && (! $multiplier_ignore_flag)) ) {
%  # total usage didn't equal formula and there were no ignore set
%  $error = "error: total usage '$input_tu' '$tu' must follow the formula<br>"
%          ." total_usage = (current_reading - previous_reading) * meter_multiplier<br>"
%          ." unless the meter multiplier ignore flag '$multiplier_ignore_flag' is set.<br>";
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
% # measured_demand - positive integer
% my $md = $usage_hash{'measured_demand'};
% if ( ($md < 0) || ($md !~ /^\d+$/) ) {
%  $error = "error: measured demand '$md' must follow the rule<br>"
%          ." of being a positive integer.<br>";
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
% # billed_demand - positive integer
% my $bd = $usage_hash{'billed_demand'};
% if ( ($bd < 0) || ($bd !~ /^\d+$/) ) {
%   $error = "error: billed demand '$bd' must follow the rule<br>"
%          ." of being a positive integer.<br>";
%   $cgi->param('error', $error);
%   print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
% # meter_number - alpha numeric value
% my $mn = $usage_hash{'meter_number'};
% if ( $mn !~ /^[a-z0-9]+$/i ) {
%  $error = "error: meter number '$mn' must follow the rule<br>"
%          ." of being a alpha numeric value.<br>";
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
% }
%
%
%# convert the field date to it strtime
%$prev_date = FS::usage_elec::to_usage_elec_time($cgi->param('prev_date'));
%unless ($prev_date) {
%  $error = "error: unable to convert prev_date ".$cgi->param('prev_date')
%          ." to a usable time for usage_elec\n";
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
%}
%
%$curr_date = FS::usage_elec::to_usage_elec_time($cgi->param('curr_date'));
%unless ($curr_date) {
%  $error = "error: unable to convert curr_date ".$cgi->param('curr_date')
%          ." to a usable time for usage_elec\n";
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
%}
%
%$_date = time;
%
%$usage_hash{prev_date} = $prev_date;
%$usage_hash{curr_date} = $curr_date;
%$usage_hash{_date} = $_date;
%
%my $new = new FS::usage_elec( \%usage_hash );
%
%if ( $svcnum ) {
%  $error = $new->insert_usage;
%} else {
%  $error = "error: can't insert data into usage_elec table without a "
%          ."service number\n"
%} 
%
%if ($error) {
%  # handle can't insert data into usage_elec
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
%} else {
%  # look like the data has been inserted into usage_elec successfully
%  # now let generate the bill
%  $error = FS::usage_elec::billing_call($new);
%  if ($error) {
%    # handle can't execute billing
%    $error = "error: Execution of billing failed.\n"
%            ."$error";
%    # delete the usage_elec that was just entered because billing failed
%    $new->delete; 
%    $cgi->param('error', $error);
%    print $cgi->redirect(popurl(2). "usage_elec_manual_input.cgi?"
%               . $cgi->query_string );
%  }
%
%  print $cgi->redirect(popurl(3). "view/svc_external.cgi?$svcnum");
%}
%
%

