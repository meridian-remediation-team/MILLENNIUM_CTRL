#!/usr/bin/perl
#
# scan_dates.pl
# Meridian Remediation Team -- 1999-08-07
#
# Deep scanner for 2-digit year patterns in production binaries and
# source files. Searches for YY-format date handling, 2-digit year
# storage fields, and known-bad date function calls.
#
# This script has found things that manual review missed entirely.
# Run it on everything. Twice.
#
# Usage:
#   ./scan_dates.pl --target=<glob>             (basic scan)
#   ./scan_dates.pl --deep --target=<glob>      (scan binaries too)
#   ./scan_dates.pl --deep --target=WEST-FIN-*  (remote node scan)
#
# Output format:
#   NODE: /path/to/file    line NNN  PATTERN in FUNCTION_NAME
#
# Exit codes:
#   0  -- no vulnerabilities found
#   1  -- vulnerabilities found (expected in 1999, unfortunately)
#   2  -- scan error
#

use strict;
use warnings;
use Getopt::Long;
use File::Find;
use File::Basename;

my $VERSION = '1.9';
my $AUTHOR  = 'meridian-ops';

# ------------------------------------------------------------------- #
# Options                                                               #
# ------------------------------------------------------------------- #
my $opt_deep   = 0;
my $opt_target = '';
my $opt_output = '';
my $opt_help   = 0;

GetOptions(
    'deep'     => \$opt_deep,
    'target=s' => \$opt_target,
    'output=s' => \$opt_output,
    'help'     => \$opt_help,
) or die "scan_dates.pl: invalid options. Use --help.\n";

if ($opt_help) {
    print_help();
    exit 0;
}

if (!$opt_target) {
    die "scan_dates.pl: --target is required.\n";
}

# ------------------------------------------------------------------- #
# Pattern library                                                       #
# Add patterns here as new vulnerability types are discovered.         #
# ------------------------------------------------------------------- #

my @SOURCE_PATTERNS = (
    # COBOL: PIC 99 year fields
    {
        pattern => qr/PIC\s+9{1,2}\s*(?=.*YEAR|.*YR|.*DATE)/i,
        label   => 'COBOL PIC-99 year field',
        risk    => 'HIGH',
    },
    # C: 2-digit year format strings
    {
        pattern => qr/"%\s*0?2d".*(?:year|yr)/i,
        label   => 'C format string 2-digit year',
        risk    => 'HIGH',
    },
    # C: tm_year used without +1900
    {
        pattern => qr/tm_year(?!\s*\+\s*1900)/,
        label   => 'C tm_year without +1900 offset',
        risk    => 'HIGH',
    },
    # C/C++: strftime with %y
    {
        pattern => qr/strftime.*%y/i,
        label   => 'strftime with 2-digit year format',
        risk    => 'HIGH',
    },
    # Generic: hardcoded 19 prefix assumption
    {
        pattern => qr/"19"\s*\.\s*\$?(?:year|yr|yy)/i,
        label   => 'hardcoded "19" year prefix',
        risk    => 'CRITICAL',
    },
    # Perl: localtime year without +1900
    {
        pattern => qr/\(localtime\)[^;]*\[5\](?!\s*\+\s*1900)/,
        label   => 'Perl localtime year without +1900',
        risk    => 'HIGH',
    },
    # Shell: date +%y
    {
        pattern => qr/date\s+.*%y/i,
        label   => 'shell date command with 2-digit year',
        risk    => 'MEDIUM',
    },
    # COBOL: ACCEPT DATE giving 6-digit YYMMDD
    {
        pattern => qr/ACCEPT\s+\S+\s+FROM\s+DATE(?!\s+YYYYMMDD)/i,
        label   => 'COBOL ACCEPT DATE (6-digit, not 8-digit)',
        risk    => 'HIGH',
    },
);

my @BINARY_SIGNATURES = (
    # Compiled format strings with 2-digit year
    qr/\x25\x30\x32\x64.{0,20}(?:year|yr)/i,
    # "19" prefix in data segments
    qr/\x31\x39(?:[\x30-\x39]{2})/,
);

# ------------------------------------------------------------------- #
# Main                                                                  #
# ------------------------------------------------------------------- #

print "[scan_dates.pl] Muffett Date Pattern Scanner v$VERSION\n";
print "[scan_dates.pl] Scanning for 2-digit year patterns in production binaries...\n";
print "[scan_dates.pl] \n";

my @targets = glob($opt_target);
if (!@targets) {
    # Try as remote node prefix
    @targets = resolve_remote_nodes($opt_target);
}

my $total_vulns = 0;
my $total_files = 0;
my $critical_count = 0;

for my $target (@targets) {
    my ($node_vulns, $node_files) = scan_target($target);
    $total_vulns += $node_vulns;
    $total_files += $node_files;
}

print "[scan_dates.pl] \n";
print "[scan_dates.pl] Total vulnerabilities found: $total_vulns\n";

if ($total_vulns > 0) {
    my $devs = 3;
    my $minutes_per_vuln = 10;
    my $total_minutes = $total_vulns * $minutes_per_vuln;
    my $hours = int($total_minutes / 60);
    my $mins  = $total_minutes % 60;
    printf("[scan_dates.pl] Estimated manual patch time at %d devs: %dh %02dm\n",
           $devs, $hours, $mins);

    # Check for scheduled batch jobs
    check_scheduled_jobs();

    exit 1;
} else {
    print "[scan_dates.pl] No vulnerabilities found. Verify manually before trusting this.\n";
    exit 0;
}


# ------------------------------------------------------------------- #
# Subroutines                                                           #
# ------------------------------------------------------------------- #

sub scan_target {
    my ($target) = @_;
    my $vuln_count = 0;
    my $file_count = 0;

    my @files;
    if (-d $target) {
        find(sub { push @files, $File::Find::name if -f }, $target);
    } else {
        @files = ($target);
    }

    for my $file (@files) {
        $file_count++;
        my ($fvulns) = scan_file($file, $target);
        $vuln_count += $fvulns;
    }

    return ($vuln_count, $file_count);
}

sub scan_file {
    my ($file, $node) = @_;
    my $vuln_count = 0;

    my $is_binary = is_binary_file($file);

    if ($is_binary && !$opt_deep) {
        return (0);
    }

    open(my $fh, '<', $file) or do {
        warn "scan_dates.pl: cannot open $file: $!\n";
        return (0);
    };

    if ($is_binary) {
        # Binary scan: read whole file, match signatures
        local $/;
        my $content = <$fh>;
        for my $sig (@BINARY_SIGNATURES) {
            if ($content =~ $sig) {
                printf("%-30s %-40s %s\n",
                       $node . ":", $file, "binary signature match");
                $vuln_count++;
            }
        }
    } else {
        # Source scan: line by line
        my $lineno = 0;
        while (my $line = <$fh>) {
            $lineno++;
            chomp $line;
            for my $pat (@SOURCE_PATTERNS) {
                if ($line =~ $pat->{pattern}) {
                    # Extract function context if possible
                    my $context = extract_context($line);
                    printf("%-30s %-45s line %-5d %s in %s\n",
                           $node . ":", $file, $lineno,
                           $pat->{label}, $context);
                    $vuln_count++;
                }
            }
        }
    }

    close($fh);
    return ($vuln_count);
}

sub extract_context {
    my ($line) = @_;
    # Try to extract function/procedure name from line
    if ($line =~ /(?:PROCEDURE|SUBROUTINE|FUNCTION|SUB)\s+(\w+)/i) {
        return $1;
    }
    if ($line =~ /(?:void|int|char|static)\s+(\w+)\s*\(/) {
        return $1;
    }
    if ($line =~ /(\w+):/) {
        return $1;
    }
    return "(unknown)";
}

sub is_binary_file {
    my ($file) = @_;
    my $ext = (fileparse($file, qr/\.[^.]*/i))[2];
    return 1 if $ext =~ /^\.(so|o|a|exe|bin|out)$/i;
    return 0;
}

sub resolve_remote_nodes {
    my ($pattern) = @_;
    # In production: would SSH to each node and scan remotely.
    # For now: return pattern as-is and let glob handle it.
    return glob($pattern);
}

sub check_scheduled_jobs {
    # Check if billrun or other critical jobs are scheduled soon
    my $cron_output = `crontab -l 2>/dev/null`;
    if ($cron_output =~ /billrun/) {
        print "[scan_dates.pl] CRITICAL: billrun found in crontab -- check rollover timing\n";
    }
}

sub print_help {
    print <<END;
scan_dates.pl v$VERSION -- Meridian Y2K Date Pattern Scanner

Usage:
  scan_dates.pl [options] --target=<path_or_glob>

Options:
  --target=<path>   File, directory, or node glob to scan
  --deep            Also scan binary files (slower)
  --output=<file>   Write results to file in addition to stdout
  --help            Show this message

Examples:
  scan_dates.pl --target=/usr/local/lib/fincore.so
  scan_dates.pl --deep --target=WEST-FIN-*
  scan_dates.pl --target=/opt/billing/ --output=/tmp/billing_scan.txt

Exit codes:
  0  No vulnerabilities found
  1  Vulnerabilities found
  2  Scan error
END
}
