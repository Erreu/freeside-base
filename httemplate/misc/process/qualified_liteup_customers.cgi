<% include("/elements/header.html",'LITEUP') %>
%
%  my $fh = $cgi->upload('textfile');
%
%  my $action = $cgi->param('action');
%  #print '<br><br>'.$action.'<br><br>';
%  # read the text file and test for accuracy
%  # we are expection each line of the file to contain
%  # ESIIDxxxxADDRESSxxxxCITYxxxxSTATEZIPxxxxLITEUPDURATION
%  # whese x is multiple whitespace
%  #
%  my $line;
%  my @newlist;
%  my $i =0;
%  while ( defined($line=<$fh>) ) {
%    $newlist[$i] = [ split /\s{2,}/, $line ];
%    $i++;
%  }
%
%  if ($action eq 'Get Report') { #liteup audit
%    my ($beg,$end) = FS::UI::Web::parse_beginning_ending($cgi);
%    $beg = str2time("1/1/2008") unless ($beg);
%    $end = str2time(`date`) unless ($end);
%    print '<h3>Audit from ' . time2str("%D",$beg) .' through '. 
%          ($end == 4294967295 ? 'NOW' : time2str("%D",$end)) .'</h3>';
%
%    my @cust_bills = qsearch ( {
%             'table' => 'cust_bill_pkg_detail',
%             'hashref' => { 'curr_date' => { 
%                                   'op' => '>=',
%                                  'value' => "$beg",
%                                            }
%                          },
%             'extra_sql'=> "AND curr_date <= $end
%                            AND discount1_rate > 0
%                            ORDER BY esiid ASC",
%                               });
%    my %liteup_cust;
%    foreach my $cust_bill_pkg (@cust_bills) {
%      if ($cust_bill_pkg->discount1_rate) {
%        $cust_bill_pkg->esiid =~ /^\s*(\d{4})\d+$/;
%        $liteup_cust{$1}{$cust_bill_pkg->esiid}{$cust_bill_pkg->curr_date}{discount} = 
%                                                 $cust_bill_pkg->discount1_total;
%        $liteup_cust{$1}{$cust_bill_pkg->esiid}{$cust_bill_pkg->curr_date}{usage} = 
%                                          int($cust_bill_pkg->energy_usage);
%        # let get the custnum
%        my $cust_bill = qsearchs( {
%                         'table' => 'cust_bill',
%                         'hashref' => { 'invnum' => { 'op' => '=',
%                                                      'value' => $cust_bill_pkg->invnum,
%                                                    }
%                                      }
%                               });
%        $liteup_cust{$1}{$cust_bill_pkg->esiid}{$cust_bill_pkg->curr_date}{custnum} = 
%                                       $cust_bill->custnum;
%      }
%    }

%    foreach my $esiid_4 (sort keys %liteup_cust) {
%      print '<br><FONT COLOR="#FF0000"><b>'. $esiid_4 .'</FONT></b><br>';
%      my $total = 0;
%      my $total_usage = 0;
%      foreach my $esiid (sort keys %{$liteup_cust{$esiid_4}}) {
%        print '----'. $esiid .'<br>';
%        foreach my $date (sort keys %{$liteup_cust{$esiid_4}{$esiid}}) {
%          print '&nbsp;'x10
%               . $liteup_cust{$esiid_4}{$esiid}{$date}{custnum} 
%               . ':'. time2str("%D",$date) 
%               . ':'. $liteup_cust{$esiid_4}{$esiid}{$date}{usage} .'kWh' 
%               . ':$'. $liteup_cust{$esiid_4}{$esiid}{$date}{discount} 
%               . '<br>';
%          $total += $liteup_cust{$esiid_4}{$esiid}{$date}{discount};
%          $total_usage += $liteup_cust{$esiid_4}{$esiid}{$date}{usage};
%        }
%      }
%      #printf "==<FONT COLOR="#FF0000"><b>%dkWh'  . $total_usage .'kWh'.':$'. $total .'</FONT></b><br>';
%      printf "==<FONT COLOR='#FF0000'><b>%dkWh:\$%.2f</FONT></b><br>",$total_usage,$total;
%    }
%
%  }
%elsif ($action eq 'Process List') {
%    print 'UNDER CONSTRUCTION<BR>';
%#  my @cust_main = qsearch ( {
%#                         'table'     => 'cust_main',
%#                         'extra_sql' => 'ORDER BY custnum ASC'
%#                        } );
%
%#  my %liteup_cust;
%#  $i=1;
%#  foreach my $cust (@cust_main) {
%#    if ($i<2000) {
%#      #print $cust->custnum . "=>" . $cust->first . "," . $cust->last . "<br>";
%#      #print $cust->custnum . "<br>";
%#      my @packages = get_packages($cust);
%#      foreach my $cust_pkg (@packages) {
%#        my $part_pkg = $cust_pkg->part_pkg;
%##        print 'PKG: '. $part_pkg->pkg . "<br>";
%#        my @part_pkg_option = $part_pkg->part_pkg_option;
%#        my @cust_svc = $cust_pkg->cust_svc(3);
%#        foreach my $custsvc (@cust_svc) {
%#          my $liteup_discount;
%#          foreach my $pkg_option (@part_pkg_option) {
%##            print 'optionname:'.$pkg_option->optionname.'-----optionvalue:'
%##                 .$pkg_option->optionvalue .'<br>';
%#            if ($pkg_option->optionname eq 'rate1_discount' && 
%#                $pkg_option->optionvalue) {
%#              $liteup_discount = $pkg_option->optionvalue;
%#            }
%#          }
%
%#          my $svc_x = $custsvc->svc_x;
%##          print "svcnum = " . $custsvc->svcnum . "<br>" if $custsvc;
%##          print $svc_x->id . ':'. $svc_x->title .'<br>';

%#          if ($svc_x->title eq 'ESIID' && $svc_x->id && $liteup_discount) {
%#            print $cust->custnum . "=>" . $cust->first . "," . $cust->last . "<br>";
%#            print 'PKG: '. $part_pkg->pkg . "<br>";
%#            print $svc_x->id . ':'. $svc_x->title .'<br>';
%#            print 'disount:' . $liteup_discount . '<br>;
%#            $liteup_cust{$cust->custnum}{first} = $cust->first;
%#            $liteup_cust{$cust->custnum}{last} = $cust->last;
%#            $liteup_cust{$cust->custnum}{esiid} = $cust->esiid;
%#            $liteup_cust{$cust->custnum}{discount} = $liteup_discount;
%#          }
%#        }
%#      }
%#    }
%#    $i++;
%#  }
%
%} #end elsif
%#  sub get_packages {
%#    my $cust_main = shift or return undef;
%
%
%#    return $cust_main->ncancelled_pkgs();

%#  }
<% include('/elements/footer.html') %>
