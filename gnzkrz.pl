#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use MeToo;
use DBI;

my $html_header = <<END;
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<link rel="stylesheet" href="{base}/_a/style.css">
<title>{title}</title>
</head>
<body>
END

my $html_footer = <<END;
</body>
</html>
END

sub connect_db;
sub encode_id($);
sub decode_id($);
sub error_unknown_url_id($);
sub error_invalid_url($);

get '/' => sub {
	my ($dbh, $prefix) = connect_db;

	my $sth = $dbh->prepare("SELECT count(1) AS url_count, sum(access_count) AS access_count FROM ${prefix}_urls WHERE enabled = 1");
	$sth->execute;
	my $row = $sth->fetchrow_hashref;
	$sth->finish;
	$dbh->disconnect;

	t(<<END, base => base, url_count => $row->{url_count}, access_count => $row->{access_count}, title => "krzz.de | URL Shortener");
$html_header
<div id=main>
<h1>Enter URL you want to shorten:</h1>
<form action="{base}/_/save" method=post>
<input id=url name=url placeholder="URL, e.g. http://example.com/" type=url required autofocus>
<button type=submit id=submit>Shorten</button>
</form>
</div>
<div id=fineprint>
<a href="{base}/_a/faq.html">FAQ</a> | <a href="mailto:admin\@krzz.de">Contact</a> | <a href="https://github.com/akrennmair/gnzkrz">Show me the code!</a> | <a href="{base}/_a/imprint.html">Impressum</a>
<br>
shortened {url_count} URLs that were accessed {access_count} times.
</div>
$html_footer
END
};

post '/_/save' => sub {
	my $url = params->{url};

	if ($url !~ /^https?:\/\/[^\/]+\/?.*$/) {
		return error_invalid_url($url);
	}

	my $encoded_id = save_url($url);
	redirect base_url . "/_/preview/$encoded_id";
};

get '/_api/save' => sub {
	my $url = params->{url};

	content_type("text/plain");

	if ($url !~ /^https?:\/\/[^\/]+\/?.*$/) {
		return "error: invalid URL";
	}

	my $encoded_id = save_url($url);
	t(<<END, base_url => base_url, id => $encoded_id);
{base_url}/{id}
END
};

get '/_/preview/(.*)' => sub {
	my $encoded_id = shift;

	my ($dbh, $prefix) = connect_db;
	my $sth = $dbh->prepare("SELECT url FROM ${prefix}_urls WHERE id = ? AND enabled = 1");
	$sth->execute(decode_id($encoded_id));
	my $row = $sth->fetchrow_hashref;
	if (!$row) {
		return error_unknown_url_id($encoded_id);
	}
	my $url = $row->{url};
	my $len_diff = length($url) - length(base_url . "/" . $encoded_id);

	$sth->finish;
	$dbh->disconnect;

	t(<<END, base => base, base_url => base_url, id => $encoded_id, title => "krzz.de | Preview", url => cgi->escapeHTML($url), save => $len_diff );
$html_header
<div id=main>
<h1>Preview</h1>
<a href="{url}">{url}</a> has been shortened to <a href="{base_url}/{id}">{base_url}/{id}</a>, which is {save} bytes shorter.
</div>
$html_footer
END
};

get '/(.*)' => sub {
	my $encoded_id = shift;
	my $id = decode_id($encoded_id);
	my ($dbh, $prefix) = connect_db;

	my $sth = $dbh->prepare("SELECT url FROM ${prefix}_urls WHERE id = ? AND enabled = 1");
	$sth->execute($id);
	my $row = $sth->fetchrow_hashref;

	if (!$row) {
		$sth->finish;
		$dbh->disconnect;
		return error_unknown_url_id($encoded_id);
	}
	$sth->finish;
	$sth = $dbh->prepare("UPDATE ${prefix}_urls SET access_count = access_count + 1 WHERE id = ?");
	$sth->execute($id);
	$sth->finish;
	$dbh->disconnect;
	my $url = $row->{url};

	redirect $url;
};

sub connect_db {
	my $fh;
	open($fh, '<', 'db.conf') or return undef;
	my $line = <$fh>;
	chomp($line);
	my ($user, $pass, $host, $db, $table_prefix) = split(/ /, $line);
	$table_prefix ||= "gnzkrz";
	return (DBI->connect("dbi:mysql:database=$db;host=$host", $user, $pass, { RaiseError => 1, AutoCommit => 0 }), $table_prefix);
}

sub encode_id($) {
	my $id = shift;
	my $encoded_id = "";
	my @nums = ('0'..'9','a'..'z','A'..'Z');

	while ($id > 0) {
		$encoded_id = $nums[$id % 62] . $encoded_id;
		$id = int($id / 62);
	}

	return $encoded_id;
}

sub decode_id($) {
	my $encoded_id = shift;
	my $i = 0;
	my %ch;
	foreach my $c ('0'..'9','a'..'z','A'..'Z') {
		$ch{$c} = $i;
		$i++;
	}
	my $id = 0;
	foreach my $x (split(//, $encoded_id)) {
		$id = $id*62 + $ch{$x};
	}
	return $id;
}

sub error_unknown_url_id($) {
	my $encoded_id = shift;
	return t(<<END, base => base, id => $encoded_id, title => "krzz.de | Error");
$html_header
<div id=main>
<h1>Error: unknown URL {id}!</h1>
</div>
$html_footer
END
}

sub error_invalid_url($) {
	my $url = shift;
	return t(<<END, base => base, url => cgi->escapeHTML($url), title => "krzz.de | Error");
$html_header
<div id=main>
<h1>Error: invalid URL {url}!</h1>
</div>
$html_footer
END
}

sub save_url($) {
	my $url = shift;
	my ($dbh, $prefix) = connect_db;

	my $sth = $dbh->prepare("INSERT INTO ${prefix}_urls (url, remote_addr, created, access_count, enabled) VALUES (?, ?, NOW(), 0, 1)");

	$sth->execute($url, $ENV{REMOTE_ADDR});
	my $id = $dbh->last_insert_id(undef, undef, undef, undef);

	$dbh->disconnect;

	my $encoded_id = encode_id($id);

	return $encoded_id;
}
