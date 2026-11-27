//! 每次请求时决定走哪条代理。
//!
//! 图形界面进程通常没有 `HTTPS_PROXY` 这类环境变量。Clash、Surge 一类工具
//! 把代理写进系统设置，端口各不相同，而且可能在应用已经打开之后才打开。
//! 这里在每次请求时重新读取，不把端口写死，也不沿用进程启动时的快照。

use reqwest::Url;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EnvProxy {
    pub http: Option<String>,
    pub https: Option<String>,
    pub all: Option<String>,
    pub no: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SystemProxy {
    pub kind: SystemProxyKind,
    pub host: String,
    pub port: u16,
    pub username: Option<String>,
    pub password: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SystemProxyKind {
    /// HTTP 代理，或系统里用于 HTTPS 的隧道代理。隧道仍用 HTTP CONNECT。
    Http,
    Socks,
}

pub fn configure(builder: reqwest::ClientBuilder) -> reqwest::ClientBuilder {
    builder.proxy(reqwest::Proxy::custom(proxy_for))
}

pub fn proxy_for(url: &Url) -> Option<String> {
    let env = EnvProxy::current();
    let system = if host_bypassed(url, env.no.as_deref()) || env.for_url(url).is_some() {
        None
    } else {
        system_proxy(url)
    };
    choose_proxy(url, &env, system)
}

pub fn choose_proxy(url: &Url, env: &EnvProxy, system: Option<SystemProxy>) -> Option<String> {
    if host_bypassed(url, env.no.as_deref()) {
        return None;
    }
    if let Some(proxy) = env.for_url(url) {
        return normalize_proxy_url(proxy);
    }
    system.as_ref().and_then(SystemProxy::url)
}

impl EnvProxy {
    fn current() -> Self {
        // CGI 风格的进程里忽略 HTTP_PROXY，避免请求头被外部注入代理。
        let http = if std::env::var_os("REQUEST_METHOD").is_some() {
            None
        } else {
            env_value(&["HTTP_PROXY", "http_proxy"])
        };
        Self {
            http,
            https: env_value(&["HTTPS_PROXY", "https_proxy"]),
            all: env_value(&["ALL_PROXY", "all_proxy"]),
            no: env_value(&["NO_PROXY", "no_proxy"]),
        }
    }

    fn for_url(&self, url: &Url) -> Option<&str> {
        let specific = if url.scheme() == "https" {
            self.https.as_deref()
        } else {
            self.http.as_deref()
        };
        specific.or(self.all.as_deref())
    }
}

impl SystemProxy {
    fn url(&self) -> Option<String> {
        let scheme = match self.kind {
            // 系统里的 HTTPS 项是隧道代理，不是「代理自己走 TLS」。
            SystemProxyKind::Http => "http",
            // 让 VPN 解析域名。本机 DNS 在只开代理时经常解析不到目标。
            SystemProxyKind::Socks => "socks5h",
        };
        proxy_url(
            scheme,
            &self.host,
            self.port,
            self.username.as_deref(),
            self.password.as_deref(),
        )
    }
}

fn env_value(names: &[&str]) -> Option<String> {
    names.iter().find_map(|name| {
        std::env::var(name)
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    })
}

fn normalize_proxy_url(raw: &str) -> Option<String> {
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    if raw.contains("://") {
        Some(raw.to_string())
    } else {
        Some(format!("http://{raw}"))
    }
}

pub fn host_bypassed(url: &Url, no_proxy: Option<&str>) -> bool {
    let Some(no_proxy) = no_proxy else {
        return false;
    };
    let Some(host) = url.host_str() else {
        return false;
    };
    no_proxy.split([',', ' ']).any(|entry| {
        let entry = entry.trim();
        !entry.is_empty() && host_matches_bypass(host, entry)
    })
}

fn host_matches_bypass(host: &str, entry: &str) -> bool {
    if entry == "*" {
        return true;
    }
    if let Some((addr, bits)) = entry.split_once('/') {
        return ipv4_in_cidr(host, addr, bits);
    }
    let pattern = entry.trim_start_matches('.');
    if host.eq_ignore_ascii_case(pattern) {
        return true;
    }
    let suffix = format!(".{pattern}");
    host.len() > suffix.len() && host[host.len() - suffix.len()..].eq_ignore_ascii_case(&suffix)
}

fn ipv4_in_cidr(host: &str, addr: &str, bits: &str) -> bool {
    let Ok(bits) = bits.parse::<u32>() else {
        return false;
    };
    if bits > 32 {
        return false;
    }
    let Ok(host_ip) = host.parse::<std::net::Ipv4Addr>() else {
        return false;
    };
    let Ok(net) = addr.parse::<std::net::Ipv4Addr>() else {
        return false;
    };
    if bits == 0 {
        return true;
    }
    let mask = u32::MAX << (32 - bits);
    (u32::from(host_ip) & mask) == (u32::from(net) & mask)
}

fn proxy_url(
    scheme: &str,
    host: &str,
    port: u16,
    username: Option<&str>,
    password: Option<&str>,
) -> Option<String> {
    let host = host.trim();
    if host.is_empty() || port == 0 {
        return None;
    }
    let host = if host.contains(':') && !host.starts_with('[') {
        format!("[{host}]")
    } else {
        host.to_string()
    };
    let auth = match (username.filter(|value| !value.is_empty()), password) {
        (Some(user), Some(pass)) => Some(format!(
            "{}:{}@",
            urlencoding::encode(user),
            urlencoding::encode(pass)
        )),
        (Some(user), None) => Some(format!("{}@", urlencoding::encode(user))),
        _ => None,
    };
    Some(format!(
        "{scheme}://{}{host}:{port}",
        auth.unwrap_or_default()
    ))
}

#[cfg(not(target_os = "macos"))]
fn system_proxy(_url: &Url) -> Option<SystemProxy> {
    None
}

#[cfg(target_os = "macos")]
fn system_proxy(url: &Url) -> Option<SystemProxy> {
    macos::proxy_for(url)
}

#[cfg(target_os = "macos")]
mod macos {
    use super::{SystemProxy, SystemProxyKind};
    use reqwest::Url;
    use std::ffi::CStr;
    use std::os::raw::{c_char, c_void};
    use std::ptr;

    type CFTypeRef = *const c_void;
    type CFStringRef = *const c_void;
    type CFURLRef = *const c_void;
    type CFDictionaryRef = *const c_void;
    type CFArrayRef = *const c_void;
    type CFRunLoopRef = *const c_void;
    type CFRunLoopSourceRef = *const c_void;
    type CFIndex = isize;

    const UTF8: u32 = 0x0800_0100;
    const NUMBER_INT: i32 = 9;

    #[repr(C)]
    struct StreamContext {
        version: CFIndex,
        info: *mut c_void,
        retain: *const c_void,
        release: *const c_void,
        copy_description: *const c_void,
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        static kCFRunLoopDefaultMode: CFStringRef;
        fn CFRelease(cf: CFTypeRef);
        fn CFEqual(a: CFTypeRef, b: CFTypeRef) -> u8;
        fn CFGetTypeID(cf: CFTypeRef) -> usize;
        fn CFStringGetTypeID() -> usize;
        fn CFURLGetTypeID() -> usize;
        fn CFStringGetLength(s: CFStringRef) -> CFIndex;
        fn CFStringGetMaximumSizeForEncoding(length: CFIndex, encoding: u32) -> CFIndex;
        fn CFStringGetCString(
            s: CFStringRef,
            buffer: *mut c_char,
            size: CFIndex,
            encoding: u32,
        ) -> u8;
        fn CFStringCreateWithCString(
            alloc: *const c_void,
            c_str: *const c_char,
            encoding: u32,
        ) -> CFStringRef;
        fn CFURLCreateWithBytes(
            alloc: *const c_void,
            bytes: *const u8,
            length: CFIndex,
            encoding: u32,
            base: CFURLRef,
        ) -> CFURLRef;
        fn CFURLGetString(url: CFURLRef) -> CFStringRef;
        fn CFNumberGetValue(number: CFTypeRef, kind: i32, value: *mut c_void) -> u8;
        fn CFDictionaryGetValue(dict: CFDictionaryRef, key: *const c_void) -> *const c_void;
        fn CFArrayGetCount(array: CFArrayRef) -> CFIndex;
        fn CFArrayGetValueAtIndex(array: CFArrayRef, index: CFIndex) -> *const c_void;
        fn CFRunLoopGetCurrent() -> CFRunLoopRef;
        fn CFRunLoopAddSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef, mode: CFStringRef);
        fn CFRunLoopRemoveSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef, mode: CFStringRef);
        fn CFRunLoopRunInMode(mode: CFStringRef, seconds: f64, return_after_source: u8) -> i32;
        fn CFRunLoopStop(rl: CFRunLoopRef);
    }

    #[link(name = "CFNetwork", kind = "framework")]
    extern "C" {
        static kCFProxyTypeKey: CFStringRef;
        static kCFProxyHostNameKey: CFStringRef;
        static kCFProxyPortNumberKey: CFStringRef;
        static kCFProxyUsernameKey: CFStringRef;
        static kCFProxyPasswordKey: CFStringRef;
        static kCFProxyAutoConfigurationURLKey: CFStringRef;
        static kCFProxyAutoConfigurationJavaScriptKey: CFStringRef;
        static kCFProxyTypeNone: CFStringRef;
        static kCFProxyTypeHTTP: CFStringRef;
        static kCFProxyTypeHTTPS: CFStringRef;
        static kCFProxyTypeSOCKS: CFStringRef;
        static kCFProxyTypeAutoConfigurationURL: CFStringRef;
        static kCFProxyTypeAutoConfigurationJavaScript: CFStringRef;

        fn CFNetworkCopySystemProxySettings() -> CFDictionaryRef;
        fn CFNetworkCopyProxiesForURL(url: CFURLRef, settings: CFDictionaryRef) -> CFArrayRef;
        fn CFNetworkCopyProxiesForAutoConfigurationScript(
            script: CFStringRef,
            target: CFURLRef,
            error: *mut CFTypeRef,
        ) -> CFArrayRef;
        fn CFNetworkExecuteProxyAutoConfigurationURL(
            pac: CFURLRef,
            target: CFURLRef,
            callback: extern "C" fn(*mut c_void, CFArrayRef, CFTypeRef),
            context: *mut StreamContext,
        ) -> CFRunLoopSourceRef;
    }

    #[derive(Clone)]
    enum EntryKind {
        Direct,
        Http,
        Socks,
        PacUrl(String),
        PacScript(String),
        Skip,
    }

    struct Entry {
        kind: EntryKind,
        host: String,
        port: u16,
        username: Option<String>,
        password: Option<String>,
    }

    struct PacOut {
        entries: Vec<Entry>,
    }

    pub fn proxy_for(url: &Url) -> Option<SystemProxy> {
        let target = create_url(url.as_str())?;
        let settings = unsafe { CFNetworkCopySystemProxySettings() };
        if settings.is_null() {
            release(target);
            return None;
        }
        let list = unsafe { CFNetworkCopyProxiesForURL(target, settings) };
        let entries = if list.is_null() {
            Vec::new()
        } else {
            let parsed = parse_list(list, true);
            release(list);
            parsed
        };
        release(settings);
        let chosen = match resolve(&entries, target) {
            Decision::Proxy(proxy) => Some(proxy),
            Decision::Direct | Decision::Undecided => None,
        };
        release(target);
        chosen
    }

    enum Decision {
        Direct,
        Proxy(SystemProxy),
        Undecided,
    }

    fn resolve(entries: &[Entry], target: CFURLRef) -> Decision {
        for entry in entries {
            match &entry.kind {
                EntryKind::Direct => return Decision::Direct,
                EntryKind::Http => return proxy_decision(SystemProxyKind::Http, entry),
                EntryKind::Socks => return proxy_decision(SystemProxyKind::Socks, entry),
                EntryKind::PacUrl(pac) => {
                    let nested = run_pac_url(pac, target);
                    match resolve(&nested, target) {
                        Decision::Undecided => {}
                        decision => return decision,
                    }
                }
                EntryKind::PacScript(script) => {
                    let nested = run_pac_script(script, target);
                    match resolve(&nested, target) {
                        Decision::Undecided => {}
                        decision => return decision,
                    }
                }
                EntryKind::Skip => {}
            }
        }
        Decision::Undecided
    }

    fn proxy_decision(kind: SystemProxyKind, entry: &Entry) -> Decision {
        match endpoint(kind, entry) {
            Some(proxy) => Decision::Proxy(proxy),
            None => Decision::Undecided,
        }
    }

    fn endpoint(kind: SystemProxyKind, entry: &Entry) -> Option<SystemProxy> {
        if entry.host.is_empty() || entry.port == 0 {
            return None;
        }
        Some(SystemProxy {
            kind,
            host: entry.host.clone(),
            port: entry.port,
            username: entry.username.clone(),
            password: entry.password.clone(),
        })
    }

    fn run_pac_url(pac: &str, target: CFURLRef) -> Vec<Entry> {
        let Some(pac_url) = create_url(pac) else {
            return Vec::new();
        };
        let mut out = PacOut {
            entries: Vec::new(),
        };
        let mut context = StreamContext {
            version: 0,
            info: &mut out as *mut PacOut as *mut c_void,
            retain: ptr::null(),
            release: ptr::null(),
            copy_description: ptr::null(),
        };
        let source = unsafe {
            CFNetworkExecuteProxyAutoConfigurationURL(pac_url, target, pac_callback, &mut context)
        };
        if source.is_null() {
            release(pac_url);
            return Vec::new();
        }
        unsafe {
            let loop_ = CFRunLoopGetCurrent();
            CFRunLoopAddSource(loop_, source, kCFRunLoopDefaultMode);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 3.0, 0);
            CFRunLoopRemoveSource(loop_, source, kCFRunLoopDefaultMode);
            CFRelease(source as CFTypeRef);
        }
        release(pac_url);
        out.entries
    }

    fn run_pac_script(script: &str, target: CFURLRef) -> Vec<Entry> {
        let Some(script) = cf_string(script) else {
            return Vec::new();
        };
        let mut error = ptr::null();
        let list =
            unsafe { CFNetworkCopyProxiesForAutoConfigurationScript(script, target, &mut error) };
        release(script);
        if !error.is_null() {
            release(error);
        }
        if list.is_null() {
            return Vec::new();
        }
        let entries = parse_list(list, false);
        release(list);
        entries
    }

    extern "C" fn pac_callback(info: *mut c_void, list: CFArrayRef, error: CFTypeRef) {
        if !info.is_null() && error.is_null() && !list.is_null() {
            let out = unsafe { &mut *(info as *mut PacOut) };
            out.entries = parse_list(list, false);
        }
        unsafe { CFRunLoopStop(CFRunLoopGetCurrent()) };
    }

    fn parse_list(list: CFArrayRef, allow_pac: bool) -> Vec<Entry> {
        let count = unsafe { CFArrayGetCount(list) };
        let mut entries = Vec::with_capacity(count.max(0) as usize);
        for index in 0..count {
            let item = unsafe { CFArrayGetValueAtIndex(list, index) };
            if item.is_null() {
                continue;
            }
            entries.push(parse_entry(item as CFDictionaryRef, allow_pac));
        }
        entries
    }

    fn parse_entry(dict: CFDictionaryRef, allow_pac: bool) -> Entry {
        let kind = match dict_type(dict) {
            Some(kind) if same(kind, unsafe { kCFProxyTypeNone }) => EntryKind::Direct,
            Some(kind)
                if same(kind, unsafe { kCFProxyTypeHTTP })
                    || same(kind, unsafe { kCFProxyTypeHTTPS }) =>
            {
                EntryKind::Http
            }
            Some(kind) if same(kind, unsafe { kCFProxyTypeSOCKS }) => EntryKind::Socks,
            Some(kind) if allow_pac && same(kind, unsafe { kCFProxyTypeAutoConfigurationURL }) => {
                EntryKind::PacUrl(
                    dict_url(dict, unsafe { kCFProxyAutoConfigurationURLKey }).unwrap_or_default(),
                )
            }
            Some(kind)
                if allow_pac && same(kind, unsafe { kCFProxyTypeAutoConfigurationJavaScript }) =>
            {
                EntryKind::PacScript(
                    dict_string(dict, unsafe { kCFProxyAutoConfigurationJavaScriptKey })
                        .unwrap_or_default(),
                )
            }
            _ => EntryKind::Skip,
        };
        Entry {
            kind,
            host: dict_string(dict, unsafe { kCFProxyHostNameKey }).unwrap_or_default(),
            port: dict_port(dict, unsafe { kCFProxyPortNumberKey }).unwrap_or(0),
            username: dict_string(dict, unsafe { kCFProxyUsernameKey }),
            password: dict_string(dict, unsafe { kCFProxyPasswordKey }),
        }
    }

    fn dict_type(dict: CFDictionaryRef) -> Option<CFTypeRef> {
        let value = unsafe { CFDictionaryGetValue(dict, kCFProxyTypeKey as *const c_void) };
        if value.is_null() {
            None
        } else {
            Some(value)
        }
    }

    fn dict_string(dict: CFDictionaryRef, key: CFStringRef) -> Option<String> {
        let value = unsafe { CFDictionaryGetValue(dict, key as *const c_void) };
        copy_string(value)
    }

    fn dict_url(dict: CFDictionaryRef, key: CFStringRef) -> Option<String> {
        let value = unsafe { CFDictionaryGetValue(dict, key as *const c_void) };
        if value.is_null() {
            return None;
        }
        unsafe {
            if CFGetTypeID(value) == CFURLGetTypeID() {
                return copy_string(CFURLGetString(value as CFURLRef) as CFTypeRef);
            }
        }
        copy_string(value)
    }

    fn dict_port(dict: CFDictionaryRef, key: CFStringRef) -> Option<u16> {
        let value = unsafe { CFDictionaryGetValue(dict, key as *const c_void) };
        if value.is_null() {
            return None;
        }
        let mut number: i32 = 0;
        let ok =
            unsafe { CFNumberGetValue(value, NUMBER_INT, &mut number as *mut i32 as *mut c_void) };
        if ok == 0 {
            return None;
        }
        u16::try_from(number).ok().filter(|port| *port != 0)
    }

    fn same(value: CFTypeRef, constant: CFStringRef) -> bool {
        unsafe { CFEqual(value, constant as CFTypeRef) != 0 }
    }

    fn copy_string(value: CFTypeRef) -> Option<String> {
        if value.is_null() {
            return None;
        }
        unsafe {
            if CFGetTypeID(value) != CFStringGetTypeID() {
                return None;
            }
            let length = CFStringGetLength(value as CFStringRef);
            let cap = CFStringGetMaximumSizeForEncoding(length, UTF8) + 1;
            if cap <= 1 {
                return Some(String::new());
            }
            let mut buffer = vec![0u8; cap as usize];
            let ok = CFStringGetCString(
                value as CFStringRef,
                buffer.as_mut_ptr() as *mut c_char,
                cap,
                UTF8,
            );
            if ok == 0 {
                return None;
            }
            CStr::from_ptr(buffer.as_ptr() as *const c_char)
                .to_str()
                .ok()
                .map(str::to_string)
        }
    }

    fn cf_string(text: &str) -> Option<CFStringRef> {
        let c = std::ffi::CString::new(text).ok()?;
        let string = unsafe { CFStringCreateWithCString(ptr::null(), c.as_ptr(), UTF8) };
        if string.is_null() {
            None
        } else {
            Some(string)
        }
    }

    fn create_url(text: &str) -> Option<CFURLRef> {
        if text.is_empty() {
            return None;
        }
        let url = unsafe {
            CFURLCreateWithBytes(
                ptr::null(),
                text.as_ptr(),
                text.len() as CFIndex,
                UTF8,
                ptr::null(),
            )
        };
        if url.is_null() {
            None
        } else {
            Some(url)
        }
    }

    fn release(value: CFTypeRef) {
        if !value.is_null() {
            unsafe { CFRelease(value) };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn url(raw: &str) -> Url {
        Url::parse(raw).expect("url")
    }

    fn env(https: Option<&str>, no: Option<&str>) -> EnvProxy {
        EnvProxy {
            http: None,
            https: https.map(str::to_string),
            all: None,
            no: no.map(str::to_string),
        }
    }

    fn http_proxy(port: u16) -> SystemProxy {
        SystemProxy {
            kind: SystemProxyKind::Http,
            host: "127.0.0.1".to_string(),
            port,
            username: None,
            password: None,
        }
    }

    #[test]
    fn direct_when_nothing_is_configured() {
        let chosen = choose_proxy(&url("https://api.github.com/"), &env(None, None), None);
        assert_eq!(chosen, None);
    }

    #[test]
    fn system_http_proxy_keeps_whatever_port_is_configured() {
        for port in [7890_u16, 1080, 6152, 20171] {
            let chosen = choose_proxy(
                &url("https://api.github.com/"),
                &env(None, None),
                Some(http_proxy(port)),
            );
            assert_eq!(chosen, Some(format!("http://127.0.0.1:{port}")));
        }
    }

    #[test]
    fn system_socks_proxy_resolves_dns_at_the_proxy() {
        let chosen = choose_proxy(
            &url("https://api.github.com/"),
            &env(None, None),
            Some(SystemProxy {
                kind: SystemProxyKind::Socks,
                host: "127.0.0.1".to_string(),
                port: 7891,
                username: None,
                password: None,
            }),
        );
        assert_eq!(chosen, Some("socks5h://127.0.0.1:7891".to_string()));
    }

    #[test]
    fn environment_proxy_wins_and_no_proxy_bypasses_both() {
        let target = url("https://api.github.com/");
        let chosen = choose_proxy(
            &target,
            &env(Some("http://10.0.0.8:8888"), None),
            Some(http_proxy(7890)),
        );
        assert_eq!(chosen, Some("http://10.0.0.8:8888".to_string()));

        let bypassed = choose_proxy(
            &target,
            &env(Some("http://10.0.0.8:8888"), Some("github.com")),
            Some(http_proxy(7890)),
        );
        assert_eq!(bypassed, None);
    }

    #[test]
    fn bare_environment_proxy_gets_an_http_scheme() {
        let chosen = choose_proxy(
            &url("https://example.com/"),
            &env(Some("127.0.0.1:6152"), None),
            None,
        );
        assert_eq!(chosen, Some("http://127.0.0.1:6152".to_string()));
    }

    #[test]
    fn bypass_matches_subdomains_and_cidr() {
        assert!(host_bypassed(
            &url("http://127.0.0.1:11434/"),
            Some("127.0.0.1")
        ));
        assert!(host_bypassed(
            &url("https://a.example.com/"),
            Some(".example.com")
        ));
        assert!(host_bypassed(
            &url("http://192.168.1.9/"),
            Some("192.168.1.0/24")
        ));
        assert!(!host_bypassed(
            &url("https://api.github.com/"),
            Some("example.com, 10.0.0.0/8")
        ));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn live_system_lookup_does_not_panic() {
        let github = url("https://api.github.com/");
        if let Some(proxy) = system_proxy(&github) {
            let rendered = proxy.url().expect("proxy url");
            assert!(
                rendered.starts_with("http://") || rendered.starts_with("socks5h://"),
                "{rendered}"
            );
        }
        let local = url("http://127.0.0.1:11434/v1");
        assert_eq!(system_proxy(&local), None);
    }
}
