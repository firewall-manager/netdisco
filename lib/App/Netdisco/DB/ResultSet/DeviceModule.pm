package App::Netdisco::DB::ResultSet::DeviceModule;

# 设备模块结果集类
# 提供设备模块相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

=head1 ADDITIONAL METHODS

=head2 search_by_field( \%cond, \%attrs? )

This variant of the standard C<search()> method returns a ResultSet of Device
Module entries. It is written to support web forms which accept fields that
match and locate Device Modules in the database.

The hashref parameter should contain fields from the Device Module table
which will be intelligently used in a search query.

In addition, you can provide the key C<matchall> which, given a True or False
value, controls whether fields must all match or whether any can match, to
select a row.

Supported keys:

=over 4

=item matchall

If a True value, fields must all match to return a given row of the Device
table, otherwise any field matching will cause the row to be included in
results.

=item description

Can match the C<description> field as a substring.

=item name

Can match the C<name> field as a substring.

=item type

Can match the C<type> field as a substring.

=item model

Can match the C<model> field as a substring (case sensitive).

=item serial

Can match the C<serial> field as a substring (case sensitive).

=item class

Will match exactly the C<class> field.

=item ips

List of Device IPs containing modules.

=back

=cut

# 按字段搜索
# 支持Web表单的智能设备模块搜索功能
sub search_by_field {
    my ( $rs, $p, $attrs ) = @_;

    die "condition parameter to search_by_field must be hashref\n"
        if ref {} ne ref $p
            or 0 == scalar keys %$p;

    my $op = $p->{matchall} ? '-and' : '-or';

    return $rs->search_rs( {}, $attrs )->search(
        {   $op => [
                (   $p->{description}
                    ? ( 'me.description' =>
                            { '-ilike' => "\%$p->{description}\%" } )
                    : ()
                ),
                (   $p->{name}
                    ? ( 'me.name' => { '-ilike' => "\%$p->{name}\%" } )
                    : ()
                ),
                (   $p->{type}
                    ? ( 'me.type' => { '-ilike' => "\%$p->{type}\%" } )
                    : ()
                ),
                (   $p->{model}
                    ? ( 'me.model' => { '-like' => "\%$p->{model}\%" } )
                    : ()
                ),
                (   $p->{serial}
                    ? ( 'me.serial' => { '-like' => "\%$p->{serial}\%" } )
                    : ()
                ),

                (   $p->{class}
                    ? ( 'me.class' => { '-in' => $p->{class} } )
                    : ()
                ),
                ( $p->{ips} ? ( 'me.ip' => { '-in' => $p->{ips} } ) : () ),
            ],
        }
    );
}

1;
