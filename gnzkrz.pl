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
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="{base}/_a/css/bootstrap.min.css">
<style>
body { padding-top: 60px; }
</style>
<title>{title}</title>
<!--[if lt IE 9]>
<script src="http://html5shim.googlecode.com/svn/trunk/html5.js"></script>
<![endif]-->
</head>
<body>
END

my $html_footer = <<END;
</body>
</html>
END

sub get_menu($) {
	my $active = shift;
	my $home_active = ($active eq "home" ? ' class="active"' : "");
	my $faq_active = ($active eq "faq" ? ' class="active"' : "");
	my $imprint_active = ($active eq "imprint" ? ' class="active"' : "");
	my $html_menu = <<END;
<div class="navbar navbar-fixed-top">
	<div class="navbar-inner">
		<div class="container">
			<a class="btn btn-navbar" data-toggle="collapse" data-target=".nav-collapse">
				<span class="icon-bar"></span>
				<span class="icon-bar"></span>
				<span class="icon-bar"></span>
				<span class="icon-bar"></span>
				<span class="icon-bar"></span>
			</a>
			<a class="brand" href="{base}/">krzz.de</a>
			<div class="nav-collapse">
				<ul class="nav">
					<li$home_active><a href="{base}/"><i class="icon-home icon-white"></i>Home</a></li>
					<li$faq_active><a href="{base}/_/faq"><i class="icon-book icon-white"></i>FAQ</a></li>
					<li><a href="mailto:admin\@krzz.de"><i class="icon-envelope icon-white"></i>Contact</a></li>
					<li><a href="https://github.com/akrennmair/gnzkrz"><i class="icon-file icon-white"></i>Show me the code!</a></li>
					<li$imprint_active><a href="{base}/_/imprint"><i class="icon-info-sign icon-white"></i>Impressum</a></li>
				</ul>
			</div>
		</div>
	</div>
</div>
END
	return $html_menu;
}

sub connect_db;
sub encode_id($);
sub decode_id($);
sub error_unknown_url_id($);
sub error_invalid_url($);
sub slurp($);

get '/' => sub {
	my ($dbh, $prefix) = connect_db;

	my $sth = $dbh->prepare("SELECT count(1) AS url_count, sum(access_count) AS access_count FROM ${prefix}_urls WHERE enabled = 1");
	$sth->execute;
	my $row = $sth->fetchrow_hashref;
	$sth->finish;
	$dbh->disconnect;

	my $html_menu = get_menu("home");

	t(<<END, base => base, url_count => $row->{url_count}, access_count => $row->{access_count}, title => "krzz.de | URL Shortener");
$html_header
$html_menu
<div class="container">
<h2>Shorten URL</h2>
<form action="{base}/_/save" method="post" class="well">
<label>Enter URL you want to shorten:
<input id=url name=url type=url placeholder="URL, e.g. http://example.com/" required autofocus class="input-medium" style="width: 50%">
</label>
<button class="btn btn-primary" type=submit id=submit>Shorten</button>
</form>
<small>shortened {url_count} URLs that were accessed {access_count} times.</small>
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

	my $html_menu = get_menu("preview");

	t(<<END, base => base, base_url => base_url, id => $encoded_id, title => "krzz.de | Preview", url => cgi->escapeHTML($url), save => $len_diff );
$html_header
$html_menu
<div class="container">
<h2>Preview</h2>
<a href="{url}">{url}</a> has been shortened to <a href="{base_url}/{id}">{base_url}/{id}</a>, which is {save} bytes shorter.
</div>
$html_footer
END
};

get '/_/faq' => sub {
	my $html_menu = get_menu("faq");
	my $faq_text = slurp("../_a/faq.html");
	t(<<END, base => base, base_url => base_url, title => "krzz.de | FAQ");
$html_header
$html_menu
$faq_text
$html_footer
END

};

get '/_/imprint' => sub {
	my $html_menu = get_menu("imprint");
	my $imprint_text = slurp("../_a/imprint.html");
	t(<<END, base => base, base_url => base_url, title => "krzz.de | Impressum");
$html_header
$html_menu
$imprint_text
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

	my $html_menu = get_menu("error_unknown_url");

	return t(<<END, base => base, id => $encoded_id, title => "krzz.de | Error");
$html_header
$html_menu
<div class="container">
<div class="alert alert-error">
<a class="close" data-dismiss="alert">×</a>
<strong>Error:</strong> unknown URL {id}!
</div>
</div>
$html_footer
END
}

sub error_invalid_url($) {
	my $url = shift;

	my $html_menu = get_menu("error_invalid_url");

	return t(<<END, base => base, url => cgi->escapeHTML($url), title => "krzz.de | Error");
$html_header
$html_menu
<div class="container">
<div class="alert alert-error">
<a class="close" data-dismiss="alert">×</a>
<strong>Error:</strong> invalid URL {url}!
</div>
</div>
$html_footer
END
}

sub save_url($) {
	my $url = shift;
	my $base_url = base_url;
	if (substr($url, 0, length($base_url)) eq $base_url) {
		my $rest = substr($url, length($base_url)+1, length($url));
		if ($rest !~ /^_/) {
			return $rest;
		}
	}

	my ($dbh, $prefix) = connect_db;

	my $id;

	my $sth = $dbh->prepare("SELECT id FROM ${prefix}_urls WHERE url = ? LIMIT 1");
	$sth->execute($url);
	my $row = $sth->fetchrow_hashref;
	if ($row) {
		$id = $row->{id};
	} else {
		$sth = $dbh->prepare("INSERT INTO ${prefix}_urls (url, remote_addr, created, access_count, enabled) VALUES (?, ?, NOW(), 0, 1)");
		$sth->execute($url, $ENV{REMOTE_ADDR});
		$id = $dbh->last_insert_id(undef, undef, undef, undef);
		$sth->finish;
	}

	$dbh->disconnect;

	my $encoded_id = encode_id($id);

	return $encoded_id;
}

sub slurp($) {
	my $fh;
	open($fh, '<', shift) or return "";
	my @lines = <$fh>;
	close($fh);
	return join("", @lines);
}
