package Sys::Info::Driver::OSX;
use strict;
use warnings;
use base qw( Exporter Sys::Info::Base );
use constant SYSCTL_NOT_EXISTS  =>
    qr{top    \s level \s name .+? in .+? is \s invalid}xms,
    qr{second \s level \s name .+? in .+? is \s invalid}xms,
    qr{name                    .+? in .+? is \s unknown}xms,
;
use constant RE_SYSCTL_SPLIT => qr{\n+}xms;
use constant RE_SYSCTL_ROW   => qr{:(?:\s)+?}xms;

use Capture::Tiny qw( capture );
use Carp          qw( croak   );

our $VERSION = '0.793';
our @EXPORT  = qw( fsysctl nsysctl sw_vers system_profiler );

sub system_profiler {
    # SPSoftwareDataType -> os version. user
    # SPHardwareDataType -> cpu
    # SPMemoryDataType   -> ram
    my(@types) = @_;
    my($out, $error) = capture {
        system system_profiler => '-xml', (@types ? @types : ())
    };

    require Mac::PropertyList;
    my $raw = Mac::PropertyList::parse_plist( $out )->as_perl;

    my %rv;
    foreach my $e ( @{ $raw } ) {
        next if ref $e ne 'HASH' || ! (keys %{ $e });
        my $key     = delete $e->{_dataType};
        my $value   = delete $e->{_items};
        $rv{ $key } = @{ $value } == 1 ? $value->[0] : $value;
    }

    return @types && @types == 1 ? values %rv : %rv;
}

sub sw_vers {
    my($out, $error) = capture { system 'sw_vers' };
    $_ = __PACKAGE__->trim( $_ ) for $out, $error;
    croak "Unable to capture `sw_vers`: $error" if $error;
    return map { split m{:\s+?}xms, $_ } split m{\n}xms, $out;
}

sub fsysctl {
    my $key = shift || croak 'Key is missing';
    my $rv  = _sysctl( $key );
    my $val = $rv->{bogus} ? croak "sysctl: $key is not defined"
            : $rv->{error} ? croak "Error fetching $key: $rv->{error}"
            :                $rv->{value}
            ;
    return $val;
}

sub nsysctl {
    my $key = shift || croak 'Key is missing';
    return _sysctl($key)->{value};
}

sub _sysctl {
    my($key) = @_;
    my($out, $error) = capture { system sysctl => $key };
    my %rv;
    if ( $out ) {
        foreach my $row ( split RE_SYSCTL_SPLIT, $out ) {
            chomp $row;
            next if ! $row;
            my($name, $value) = split RE_SYSCTL_ROW, $row, 2;
            if ( ! $value && $value ne '0' ) {
                croak sprintf q(Can't happen: No value in output for property )
                            . q('%s' inside row '%s' collected from key '%s'),
                                $name || q([no name]),
                                $row,
                                $key;
            }
            $rv{ $name } = $value;
        }
    }

    my $total = keys %rv;

    $error = __PACKAGE__->trim( $error ) if $error;

    return {
        value => $total > 1 ? { %rv } : $rv{ $key },
        error => $error,
        bogus => $error ? _sysctl_not_exists( $error ) : 0,
    };
}

sub _sysctl_not_exists {
    my($error) = @_;
    return if ! $error;
    foreach my $test ( SYSCTL_NOT_EXISTS ) {
        return 1 if $error =~ $test;
    }
    return 0;
}

1;

__END__

=head1 NAME

Sys::Info::Driver::OSX - OSX driver for Sys::Info

=head1 SYNOPSIS

    use Sys::Info::Driver::OSX;

=head1 DESCRIPTION

This is the main module in the C<OSX> driver collection.

=head1 METHODS

None.

=head1 FUNCTIONS

=head2 fsysctl

f(atal)sysctl().

=head2 nsysctl

n(ormal)sysctl.

=head2 system_profiler

System call to system_profiler.

=head2 sw_vers

System call to sw_vers.

=cut
