package App::Netdisco::Builder;

use strict;
use warnings;

use File::Spec; # 核心模块
use Module::Build;
@App::Netdisco::Builder::ISA = qw(Module::Build);

# 执行Python环境安装
# 该方法用于安装Netdisco所需的Python依赖包
sub ACTION_python {
    my $self = shift;
    require App::Netdisco::Util::Python;
    $self->do_system( App::Netdisco::Util::Python::py_install() );
}

# 执行安装操作
# 该方法重写了Module::Build的install动作，在安装完成后自动执行Python环境安装
sub ACTION_install {
    my $self = shift;
    $self->SUPER::ACTION_install;  # 调用父类的install方法
    $self->ACTION_python;          # 执行Python环境安装
}

1;
