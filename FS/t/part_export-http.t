BEGIN { $| = 1; print "1..1\n" }
END {print "not ok 1\n" unless $loaded;}
use FS::part_export::http;
$loaded=1;
print "ok 1\n";
