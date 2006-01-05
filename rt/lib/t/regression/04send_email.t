#!/usr/bin/perl -w

use strict;
use Test::More tests => 137;
use RT;
RT::LoadConfig();
RT::Init;
use RT::EmailParser;
use RT::Tickets;
use RT::Action::SendEmail;

my @_outgoing_messages;
my @scrips_fired;

#We're not testing acls here.
my $everyone = RT::Group->new($RT::SystemUser);
$everyone->LoadSystemInternalGroup('Everyone');
$everyone->PrincipalObj->GrantRight(Right =>'SuperUser');


is (__PACKAGE__, 'main', "We're operating in the main package");


{
no warnings qw/redefine/;
sub RT::Action::SendEmail::SendMessage {
        my $self = shift;
        my $MIME = shift;

        main::_fired_scrip($self->ScripObj);
        main::ok(ref($MIME) eq 'MIME::Entity', "hey, look. it's a mime entity");
}

}

# instrument SendEmail to pass us what it's about to send.
# create a regular ticket

my $parser = RT::EmailParser->new();


# Let's test to make sure a multipart/report is processed correctly
my $content =  `cat $RT::BasePath/lib/t/data/multipart-report` || die "couldn't find new content";
# be as much like the mail gateway as possible.
use RT::Interface::Email;
                                  
my %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
my $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
my $tick= $tickets->First();
isa_ok($tick, "RT::Ticket", "got a ticket object");
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Content =~ /The original message was received/, "It's the bounce");


# make sure it fires scrips.
is ($#scrips_fired, 1, "Fired 2 scrips on ticket creation");

undef @scrips_fired;




$parser->ParseMIMEEntityFromScalar('From: root@localhost
To: rt@example.com
Subject: This is a test of new ticket creation as an unknown user

Blah!
Foob!');

                                  
use Data::Dumper;

my $ticket = RT::Ticket->new($RT::SystemUser);
my  ($id,  undef, $msg ) = $ticket->Create(Requestor => ['root@localhost'], Queue => 'general', Subject => 'I18NTest', MIMEObj => $parser->Entity);
ok ($id,$msg);
$tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
 $tick = $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);
ok ($tick->Subject eq 'I18NTest', "failed to create the new ticket from an unprivileged account");

# make sure it fires scrips.
is ($#scrips_fired, 1, "Fired 2 scrips on ticket creation");
# make sure it sends an autoreply
# make sure it sends a notification to adminccs


# we need to swap out SendMessage to test the new things we care about;
&utf8_redef_sendmessage;

# create an iso 8859-1 ticket
@scrips_fired = ();

$content =  `cat $RT::BasePath/lib/t/data/new-ticket-from-iso-8859-1` || die "couldn't find new content";



$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
use RT::Interface::Email;
                           
 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
 $tick = $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Content =~ /H\x{e5}vard/, "It's signed by havard. yay");


# make sure it fires scrips.
is ($#scrips_fired, 1, "Fired 2 scrips on ticket creation");
# make sure it sends an autoreply


# make sure it sends a notification to adminccs

# If we correspond, does it do the right thing to the outbound messages?

$parser->ParseMIMEEntityFromScalar($content);
  ($id, $msg) = $tick->Comment(MIMEObj => $parser->Entity);
ok ($id, $msg);

$parser->ParseMIMEEntityFromScalar($content);
($id, $msg) = $tick->Correspond(MIMEObj => $parser->Entity);
ok ($id, $msg);





# we need to swap out SendMessage to test the new things we care about;
&iso8859_redef_sendmessage;
$RT::EmailOutputEncoding = 'iso-8859-1';
# create an iso 8859-1 ticket
@scrips_fired = ();

 $content =  `cat $RT::BasePath/lib/t/data/new-ticket-from-iso-8859-1` || die "couldn't find new content";
# be as much like the mail gateway as possible.
use RT::Interface::Email;
                                  
 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
$tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
 $tick = $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Content =~ /H\x{e5}vard/, "It's signed by havard. yay");


# make sure it fires scrips.
is ($#scrips_fired, 1, "Fired 2 scrips on ticket creation");
# make sure it sends an autoreply


# make sure it sends a notification to adminccs


# If we correspond, does it do the right thing to the outbound messages?

$parser->ParseMIMEEntityFromScalar($content);
 ($id, $msg) = $tick->Comment(MIMEObj => $parser->Entity);
ok ($id, $msg);

$parser->ParseMIMEEntityFromScalar($content);
($id, $msg) = $tick->Correspond(MIMEObj => $parser->Entity);
ok ($id, $msg);


sub _fired_scrip {
        my $scrip = shift;
        push @scrips_fired, $scrip;
}       

sub utf8_redef_sendmessage {
    no warnings qw/redefine/;
    eval ' 
    sub RT::Action::SendEmail::SendMessage {
        my $self = shift;
        my $MIME = shift;

        my $scrip = $self->ScripObj->id;
        ok(1, $self->ScripObj->ConditionObj->Name . " ".$self->ScripObj->ActionObj->Name);
        main::_fired_scrip($self->ScripObj);
        $MIME->make_singlepart;
        main::ok( ref($MIME) eq \'MIME::Entity\',
                  "hey, look. it\'s a mime entity" );
        main::ok( ref( $MIME->head ) eq \'MIME::Head\',
                  "its mime header is a mime header. yay" );
        main::ok( $MIME->head->get(\'Content-Type\') =~ /utf-8/,
                  "Its content type is utf-8" );
        my $message_as_string = $MIME->bodyhandle->as_string();
        use Encode;
        $message_as_string = Encode::decode_utf8($message_as_string);
        main::ok(
            $message_as_string =~ /H\x{e5}vard/,
"The message\'s content contains havard\'s name. this will fail if it\'s not utf8 out");

    }';
}

sub iso8859_redef_sendmessage {
    no warnings qw/redefine/;
    eval ' 
    sub RT::Action::SendEmail::SendMessage {
        my $self = shift;
        my $MIME = shift;

        my $scrip = $self->ScripObj->id;
        ok(1, $self->ScripObj->ConditionObj->Name . " ".$self->ScripObj->ActionObj->Name);
        main::_fired_scrip($self->ScripObj);
        $MIME->make_singlepart;
        main::ok( ref($MIME) eq \'MIME::Entity\',
                  "hey, look. it\'s a mime entity" );
        main::ok( ref( $MIME->head ) eq \'MIME::Head\',
                  "its mime header is a mime header. yay" );
        main::ok( $MIME->head->get(\'Content-Type\') =~ /iso-8859-1/,
                  "Its content type is iso-8859-1 - " . $MIME->head->get("Content-Type") );
        my $message_as_string = $MIME->bodyhandle->as_string();
        use Encode;
        $message_as_string = Encode::decode("iso-8859-1",$message_as_string);
        main::ok(
            $message_as_string =~ /H\x{e5}vard/, "The message\'s content contains havard\'s name. this will fail if it\'s not utf8 out");

    }';
}

# {{{ test a multipart alternative containing a text-html part with an umlaut

 $content =  `cat $RT::BasePath/lib/t/data/multipart-alternative-with-umlaut` || die "couldn't find new content";

$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
&umlauts_redef_sendmessage;

 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
 $tick = $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Content =~ /causes Error/, "We recorded the content right as text-plain");
is ($tick->Transactions->First->Attachments->Count , 3 , "Has three attachments, presumably a text-plain, a text-html and a multipart alternative");

sub umlauts_redef_sendmessage {
    no warnings qw/redefine/;
    eval 'sub RT::Action::SendEmail::SendMessage { }';
}

# }}}

# {{{ test a text-html message with an umlaut

 $content =  `cat $RT::BasePath/lib/t/data/text-html-with-umlaut` || die "couldn't find new content";

$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
&text_html_umlauts_redef_sendmessage;

 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
 $tick = $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Attachments->First->Content =~ /causes Error/, "We recorded the content as containing 'causes error'");
ok ($tick->Transactions->First->Attachments->First->ContentType =~ /text\/html/, "We recorded the content as text/html");
ok ($tick->Transactions->First->Attachments->Count ==1 , "Has one attachment, presumably a text-html and a multipart alternative");

sub text_html_umlauts_redef_sendmessage {
    no warnings qw/redefine/;
    eval 'sub RT::Action::SendEmail::SendMessage { 
                my $self = shift; 
                my $MIME = shift; 
                use Data::Dumper;
                return (1) unless ($self->ScripObj->ScripActionObj->Name eq "Notify AdminCcs" );
                ok (is $MIME->parts, 2, "generated correspondence mime entityis composed of three parts");
                is ($MIME->head->mime_type , "multipart/mixed", "The first part is a multipart mixed". $MIME->head->mime_type);
                is ($MIME->parts(0)->head->mime_type , "text/plain", "The second part is a plain");
                is ($MIME->parts(1)->head->mime_type , "text/html", "The third part is an html ");
                 }';
}

# }}}

# {{{ test a text-html message with russian characters

 $content =  `cat $RT::BasePath/lib/t/data/text-html-in-russian` || die "couldn't find new content";

$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
&text_html_russian_redef_sendmessage;

 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
 $tick = $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Attachments->First->ContentType =~ /text\/html/, "We recorded the content right as text-html");
ok ($tick->Transactions->First->Attachments->Count ==1 , "Has one attachment, presumably a text-html and a multipart alternative");

sub text_html_russian_redef_sendmessage {
    no warnings qw/redefine/;
    eval 'sub RT::Action::SendEmail::SendMessage { 
                my $self = shift; 
                my $MIME = shift; 
                use Data::Dumper;
                return (1) unless ($self->ScripObj->ScripActionObj->Name eq "Notify AdminCcs" );
                ok (is $MIME->parts, 2, "generated correspondence mime entityis composed of three parts");
                is ($MIME->head->mime_type , "multipart/mixed", "The first part is a multipart mixed". $MIME->head->mime_type);
                is ($MIME->parts(0)->head->mime_type , "text/plain", "The second part is a plain");
                is ($MIME->parts(1)->head->mime_type , "text/html", "The third part is an html ");
                my $content_1251;
                $content_1251 = $MIME->parts(1)->bodyhandle->as_string();
                ok ($content_1251 =~ qr{��e���� �e��p "����� �������� ����" �p���a�ae� �a �pe����:},
"Content matches drugim in codepage 1251" );
                 }';
}

# }}}

# {{{ test a message containing a russian subject and NO content type

unshift (@RT::EmailInputEncodings, 'koi8-r');
$RT::EmailOutputEncoding = 'koi8-r';
$content =  `cat $RT::BasePath/lib/t/data/russian-subject-no-content-type` || die "couldn't find new content";

$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
&text_plain_russian_redef_sendmessage;
 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
$tick= $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Attachments->First->ContentType =~ /text\/plain/, "We recorded the content type right");
ok ($tick->Transactions->First->Attachments->Count ==1 , "Has one attachment, presumably a text-plain");
is ($tick->Subject, "\x{442}\x{435}\x{441}\x{442} \x{442}\x{435}\x{441}\x{442}", "Recorded the subject right");
sub text_plain_russian_redef_sendmessage {
    no warnings qw/redefine/;
    eval 'sub RT::Action::SendEmail::SendMessage { 
                my $self = shift; 
                my $MIME = shift; 
                return (1) unless ($self->ScripObj->ScripActionObj->Name eq "Notify AdminCcs" );
                is ($MIME->head->mime_type , "text/plain", "The only part is text/plain ");
                 my $subject  = $MIME->head->get("subject");
                chomp($subject);
                #is( $subject ,      /^=\?KOI8-R\?B\?W2V4YW1wbGUuY39tICM3XSDUxdPUINTF09Q=\?=/ , "The $subject is encoded correctly");
		};
                 ';
}

shift @RT::EmailInputEncodings;
$RT::EmailOutputEncoding = 'utf-8';
# }}}


# {{{ test a message containing a nested RFC 822 message

 $content =  `cat $RT::BasePath/lib/t/data/nested-rfc-822` || die "couldn't find new content";
ok ($content, "Loaded nested-rfc-822 to test");

$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
&text_plain_nested_redef_sendmessage;
 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
$tick= $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);
is ($tick->Subject, "[Jonas Liljegren] Re: [Para] Niv\x{e5}er?");
ok ($tick->Transactions->First->Attachments->First->ContentType =~ /multipart\/mixed/, "We recorded the content type right");
is ($tick->Transactions->First->Attachments->Count , 5 , "Has one attachment, presumably a text-plain and a message RFC 822 and another plain");
sub text_plain_nested_redef_sendmessage {
    no warnings qw/redefine/;
    eval 'sub RT::Action::SendEmail::SendMessage { 
                my $self = shift; 
                my $MIME = shift; 
                return (1) unless ($self->ScripObj->ScripActionObj->Name eq "Notify AdminCcs" );
                is ($MIME->head->mime_type , "multipart/mixed", "It is a mixed multipart");
                 my $subject  =  $MIME->head->get("subject");
                 $subject  = MIME::Base64::decode_base64( $subject);
                chomp($subject);
		# TODO, why does this test fail
                #ok($subject =~ qr{Niv\x{e5}er}, "The subject matches the word - $subject");
		1;
                 }';
}

# }}}


# {{{ test a multipart alternative containing a uuencoded mesage generated by lotus notes

 $content =  `cat $RT::BasePath/lib/t/data/notes-uuencoded` || die "couldn't find new content";

$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
&notes_redef_sendmessage;

 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
$tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
$tick= $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Content =~ /from Lotus Notes/, "We recorded the content right");
is ($tick->Transactions->First->Attachments->Count , 3 , "Has three attachments");

sub notes_redef_sendmessage {
    no warnings qw/redefine/;
    eval 'sub RT::Action::SendEmail::SendMessage { }';
}

# }}}

# {{{ test a multipart that crashes the file-based mime-parser works

 $content =  `cat $RT::BasePath/lib/t/data/crashes-file-based-parser` || die "couldn't find new content";

$parser->ParseMIMEEntityFromScalar($content);


# be as much like the mail gateway as possible.
&crashes_redef_sendmessage;

 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
$tick= $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

ok ($tick->Transactions->First->Content =~ /FYI/, "We recorded the content right");
is ($tick->Transactions->First->Attachments->Count , 5 , "Has three attachments");

sub crashes_redef_sendmessage {
    no warnings qw/redefine/;
    eval 'sub RT::Action::SendEmail::SendMessage { }';
}



# }}}

# {{{ test a multi-line RT-Send-CC header

 $content =  `cat $RT::BasePath/lib/t/data/rt-send-cc` || die "couldn't find new content";

$parser->ParseMIMEEntityFromScalar($content);



 %args =        (message => $content, queue => 1, action => 'correspond');
 RT::Interface::Email::Gateway(\%args);
 $tickets = RT::Tickets->new($RT::SystemUser);
$tickets->OrderBy(FIELD => 'id', ORDER => 'DESC');
$tickets->Limit(FIELD => 'id' ,OPERATOR => '>', VALUE => '0');
$tick= $tickets->First();
ok ($tick->Id, "found ticket ".$tick->Id);

my $cc = $tick->Transactions->First->Attachments->First->GetHeader('RT-Send-Cc');
ok ($cc =~ /test1/, "Found test 1");
ok ($cc =~ /test2/, "Found test 2");
ok ($cc =~ /test3/, "Found test 3");
ok ($cc =~ /test4/, "Found test 4");
ok ($cc =~ /test5/, "Found test 5");

# }}}

# Don't taint the environment
$everyone->PrincipalObj->RevokeRight(Right =>'SuperUser');
1;
