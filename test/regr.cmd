@rem = ' vim: set filetype=perl: ';
@rem = ' --*-Perl-*-- ';
@rem = '
@echo off
setlocal
set PATH=%~dp0\perl\bin;%~dp0\bin;%PATH%
perl -w "%~f0" %*
exit /B %ERRORLEVEL%
';

# StorScore
#
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

use strict;
use warnings;

use File::Basename;
use Digest::MD5 'md5_hex';
use English;

use FindBin;
use lib "$FindBin::Bin\\..\\lib";

use Util;

my $script_name = basename( $PROGRAM_NAME );
my $script_dir = dirname( $PROGRAM_NAME );

unless( scalar @ARGV == 1 )
{
    warn "usage: $script_name OUTDIR\n";
    exit(-1);
}

my $outdir = "$script_dir\\$ARGV[0]";

my $total_tests = 0;
my $num_nonzero_exits = 0;

die "Directory $outdir exists\n" if -d $outdir;

mkdir( $outdir );

sub my_exec
{
    my $cmd = shift;
  
    # Unique filenames based on hash of command line
    my $base_filename = "$outdir\\" . md5_hex( $cmd );
    my $tmp_filename = "$base_filename.tmp";
    my $out_filename = "$base_filename.txt";

    execute_task( "echo $cmd > $tmp_filename" );
    my $errorlevel = execute_task( "$cmd >> $tmp_filename 2>&1" );
    execute_task( "echo ERRORLEVEL=$errorlevel >> $tmp_filename" );
  
    if( $errorlevel != 0 )
    {
        warn qq(Errorlevel $errorlevel while running "$cmd"\n);
        $num_nonzero_exits++;
    }

    # Post process raw output file to remove noise
    open( my $in, "<$tmp_filename" );
    open( my $out, ">$out_filename" );

    while( my $line = <$in> )
    {
        # Remove random temp file names
        $line =~ s/AppData\\\S*//;

        # Remove ETA info
        $line =~ s/\d{2}:\d{2}:\d{2} (AM|PM)//g;

        # Remove time from autogenerated results dir
        if( $line =~ /results/ )
        {
            $line =~ s/-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}//g;
        }

        # Remove "Done" line with overall runtime
        $line =~ s/^Done.*//;

        print $out $line;
    }

    close $in;
    close $out;

    unlink( $tmp_filename );
}
    
sub run_one
{
    my $args = shift;
    
    my $cmd = "storscore.cmd ";

    $cmd .= "--target=1234 " unless $args =~ /--target=/;

    $cmd .= "--pretend ";
    $cmd .= "--verbose ";
    $cmd .= "--noprompt ";
    
    system( "rmdir /S /Q results >NUL 2>&1" );

    my_exec( "$cmd $args" );

    $total_tests++;
}

sub run_matrix
{
    my $base_args = shift;

    my @targets = ( undef );
   
    unless( $base_args =~ /--target=/ )
    {
        push @targets, 'P:';
        push @targets, 'P:\\fake';
    }
   
    my @target_types;

    if( $base_args =~ /--target_type=/ )
    {
        @target_types = ( undef );
    }
    else
    {
        @target_types = ( qw( auto ssd hdd ) );
    }

    foreach my $target ( @targets )
    {
    foreach my $target_type ( @target_types )
    {
    foreach my $recipe ( undef, 'recipes\\corners.rcp' )
    {
        my $matrix_args = "";
        
        $matrix_args .= " --target_type=$target_type" if defined $target_type;
        $matrix_args .= " --target=$target" if defined $target;
        $matrix_args .= " --recipe=$recipe" if defined $recipe;

        run_one( "$matrix_args $base_args" );
    }
    }
    }
}

my $overall_start = time();

chdir( ".." );
    
# Preserve existing results directory
rename( "results", "results.orig" );

# Run these error conditions just once 
run_one( "--this_flag_does_not_exist" );
run_one( "--io_generator=bogus" );
run_one( "--target_type=bogus" );
run_one( "--active_range=0" );
run_one( "--active_range=110" );
run_one( "--partition_bytes=1000000000 --raw_disk" );
run_one( "--compressibility=110" );
run_one( "--raw_disk --target=P:" );
run_one( "--raw_disk --target=P:\\fake" );

# These are the defaults anyway, so just run them once
run_one( "--active_range=100" );
run_one( "--collect_smart" );
run_one( "--collect_logman" );
run_one( "--collect_power" );
run_one( "--io_generator=diskspd" );

# Run the full matrix on these
run_matrix( "" );
run_matrix( "--initialize --target_type=hdd" );
run_matrix( "--precondition --target_type=hdd" );
run_matrix( "--noinitialize --target_type=ssd" );
run_matrix( "--noprecondition --target_type=ssd" );
run_matrix( "--raw_disk --target=1234" );
run_matrix( "--active_range=1" );
run_matrix( "--active_range=50" );
run_matrix( "--partition_bytes=1000000000" );
run_matrix( "--demo_mode" );
run_matrix( "--test_id=regr" );
run_matrix( "--test_id_prefix=regr" );
run_matrix( "--nocollect_smart" );
run_matrix( "--nocollect_logman" );
run_matrix( "--nocollect_power" );
run_matrix( "--start_on_step=2" );
run_matrix( "--stop_on_step=2" );
run_matrix( "--test_time_override=42" );
run_matrix( "--warmup_time_override=42" );
run_matrix( "--compressibility=0" );
run_matrix( "--compressibility=1" );
run_matrix( "--compressibility=20" );
run_matrix( "--results_share=\\\\share\\dir" );
run_matrix( "--io_generator=sqlio" );
run_matrix( "--nopurge --target=1234" );
run_matrix( "--purge --target=P:" );
run_matrix( "--purge --target=P:\\fake" );

# Restore original results directory
system( "rmdir /S /Q results >NUL 2>&1" );
rename( "results.orig", "results" );

my $dstr = seconds_to_human( time() - $overall_start );
print "Done (took $dstr)\n";
print "Ran $total_tests tests\n";
print "Number of non-zero exits: $num_nonzero_exits\n";
print "Diff $outdir directory against another run.\n";
