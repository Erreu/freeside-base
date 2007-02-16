%
%
%my $regionnum = $cgi->param('regionnum');
%
%my $old = qsearchs('rate_region', { 'regionnum' => $regionnum } ) if $regionnum;
%
%my $new = new FS::rate_region ( {
%  map {
%    $_, scalar($cgi->param($_));
%  } ( fields('rate_region') )
%} );
%
%my $countrycode = $cgi->param('countrycode');
%my @npa = split(/\s*,\s*/, $cgi->param('npa'));
%$npa[0] = '' unless @npa;
%my @rate_prefix = map {
%                        new FS::rate_prefix {
%                          'countrycode' => $countrycode,
%                          'npa'         => $_,
%                        }
%                      } @npa;
%
%my @dest_detail = map {
%  my $ratenum = $_->ratenum;
%  new FS::rate_detail {
%    'ratenum'  => $ratenum,
%    map { $_ => $cgi->param("$_$ratenum") }
%        qw( min_included min_charge sec_granularity )
%  };
%} qsearch('rate', {} );
%
%
%my $error;
%if ( $regionnum ) {
%  $error = $new->replace($old, 'rate_prefix' => \@rate_prefix,
%                               'dest_detail' => \@dest_detail, );
%} else {
%  $error = $new->insert( 'rate_prefix' => \@rate_prefix,
%                         'dest_detail' => \@dest_detail, );
%  $regionnum = $new->getfield('regionnum');
%}
%
%if ( $error ) {
%  $cgi->param('error', $error);
%  print $cgi->redirect(popurl(2). "rate_region.cgi?". $cgi->query_string );
%} else { 
%  #print $cgi->redirect(popurl(3). "browse/rate_region.cgi");
%  print $cgi->redirect(popurl(3). "browse/rate.cgi");
%}
%
%

