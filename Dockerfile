FROM ubuntu:xenial
USER root
WORKDIR /root

# install basics
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    software-properties-common \
    wget \
 && rm -rf /var/lib/apt/lists/*

# setup wine repo
RUN dpkg --add-architecture i386 && \
    wget -nc https://dl.winehq.org/wine-builds/winehq.key && \
    apt-key add winehq.key && \
    apt-add-repository https://dl.winehq.org/wine-builds/ubuntu/ && \
    rm *.key

# install wine
RUN apt-get update && apt-get install -y --install-recommends \
    winehq-stable=4.0~xenial \
 && rm -rf /var/lib/apt/lists/*

# install winetricks
RUN wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O /usr/local/bin/winetricks && \
    chmod +x /usr/local/bin/winetricks

# tools used by wine
RUN apt-get update && apt-get install -y \
    cabextract \
    dos2unix \
    p7zip-full \
    winbind \
    zip \
 && rm -rf /var/lib/apt/lists/*

# setup wine
ENV WINEARCH win64
ENV WINEPREFIX=/opt/win
RUN winetricks win10
RUN wine cmd.exe /c echo '%ProgramFiles%'

# dotnet in wine
RUN winetricks -q dotnet472
RUN winetricks win10

# bring over the snapshots
ARG MSVC
ADD build/msvc$MSVC/snapshots snapshots

# import the snapshot files
RUN cd $WINEPREFIX/drive_c && \
    unzip -n $HOME/snapshots/CMP/files.zip

# import environment snapshot
ADD dockertools/diffenv diffenv
ADD dockertools/make-vcclang-vars make-vcclang-vars
RUN mkdir /etc/vcwine /etc/vcclang
RUN ./diffenv $HOME/snapshots/SNAPSHOT-01/env.txt $HOME/snapshots/SNAPSHOT-02/vcvars32.txt /etc/vcwine/vcvars32 && \
    ./make-vcclang-vars /etc/vcwine/vcvars32 /etc/vcclang/vcvars32
RUN ./diffenv $HOME/snapshots/SNAPSHOT-01/env.txt $HOME/snapshots/SNAPSHOT-02/vcvars64.txt /etc/vcwine/vcvars64 && \
    ./make-vcclang-vars /etc/vcwine/vcvars64 /etc/vcclang/vcvars64
RUN rm diffenv make-vcclang-vars

# 64-bit linking has trouble finding cvtres, so help it out
RUN find $WINEPREFIX -iname x86_amd64 | xargs -Ifile cp "file/../cvtres.exe" "file"

# workaround bugs in wine's cmd that prevents msvc setup bat files from working
ADD dockertools/hackvcvars hackvcvars
RUN find $WINEPREFIX/drive_c -iname v[cs]\*.bat | xargs -Ifile $HOME/hackvcvars "file" && \
    find $WINEPREFIX/drive_c -iname win\*.bat | xargs -Ifile $HOME/hackvcvars "file" && \
    rm hackvcvars

# fix inconsistent casing in filenames
RUN find $WINEPREFIX -name Include -execdir mv Include include \; || \
    find $WINEPREFIX -name Lib -execdir mv Lib lib \; || \
    find $WINEPREFIX -name \*.Lib -execdir rename 'y/A-Z/a-z/' {} \;

# vcwine
ENV MSVCARCH=64
ADD dockertools/vcwine /usr/local/bin/vcwine
ADD dockertools/clang-cl /usr/local/bin/clang-cl
ADD dockertools/lld-link /usr/local/bin/lld-link

# clean up
RUN rm -rf $HOME/snapshots

# install clang on host (for clang-cl)
ENV CLANG_HOME=/opt/bin
ENV CC=clang-cl
ENV CXX=clang-cl
RUN wget https://releases.llvm.org/7.0.0/clang+llvm-7.0.0-x86_64-linux-gnu-ubuntu-16.04.tar.xz && \
    tar xvf *.tar.xz && \
    cp -r clang*/* /opt && \
    rm -rf clang*
RUN clang-cl --version
RUN lld-link --version

# get _MSC_VER for use with clang-cl
ADD dockertools/msc_ver.cpp msc_ver.cpp
RUN vcwine cl msc_ver.cpp && \
    echo -n "MSC_VER=`vcwine msc_ver.exe`" >> /etc/vcclang/vcvars32  && \
    echo -n "MSC_VER=`vcwine msc_ver.exe`" >> /etc/vcclang/vcvars64  && \
    rm *.cpp

# make a tools dir
RUN mkdir -p $WINEPREFIX/drive_c/tools/bin
ENV WINEPATH C:\\tools\\bin

# install which in wine (for easy path debugging)
RUN wget http://downloads.sourceforge.net/gnuwin32/which-2.20-bin.zip -O which.zip && \
    cd "$WINEPREFIX/drive_c/tools" && \
    unzip $HOME/which.zip && \
    rm $HOME/which.zip
RUN vcwine which --version

# make sure we can compile with MSVC
ADD test test
RUN cd test && \
    vcwine cl helloworld.cpp && \
    vcwine helloworld.exe && \
    cd .. && rm -rf test

# make sure we can compile with clang-cl
ADD test test
RUN cd test && \
    clang-cl helloworld.cpp && \
    vcwine helloworld.exe && \
    cd .. && rm -rf test

# reboot for luck
RUN winetricks win10
RUN wineboot -r

# turn off wine's verbose logging
ENV WINEDEBUG=-all

ADD dockertools/vcentrypoint /usr/local/bin/vcentrypoint
ENTRYPOINT [ "/usr/local/bin/vcentrypoint" ]
