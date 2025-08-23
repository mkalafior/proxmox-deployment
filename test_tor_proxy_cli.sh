#!/bin/bash
# CLI-based tor-proxy service test script

# Ensure timeout command is available (install coreutils if needed on macOS)
# export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"

echo "🧅 Tor-Proxy Service CLI Test"
echo "=============================="

HOST="tor-proxy.proxmox.local"

# Test 1: SOCKS5 port connectivity
echo "🔍 Testing SOCKS5 port (9050)..."
if nc -z -w5 $HOST 9050 2>/dev/null; then
    echo "✅ SOCKS5 port (9050) is accessible"
    SOCKS5_OK=true
else
    echo "❌ SOCKS5 port (9050) is not accessible"
    SOCKS5_OK=false
fi

sleep 1

# Test 2: HTTP proxy port connectivity
echo "🔍 Testing HTTP proxy port (8118)..."
if nc -z -w5 $HOST 8118 2>/dev/null; then
    echo "✅ HTTP proxy port (8118) is accessible"
    HTTP_OK=true
else
    echo "❌ HTTP proxy port (8118) is not accessible"
    HTTP_OK=false
fi

sleep 1

# Test 3: Tor service (check if it responds to SOCKS5 handshake)
if [ "$SOCKS5_OK" = true ]; then
    echo "🔍 Testing Tor SOCKS5 handshake..."
    # Send SOCKS5 handshake and check response
    if echo -e '\x05\x01\x00' | timeout 10 nc $HOST 9050 | head -c 2 | od -An -v -t x1 | grep -q "05 00"; then
        echo "✅ Tor SOCKS5 handshake successful"
        TOR_HANDSHAKE_OK=true
    else
        echo "⚠️  Tor SOCKS5 handshake failed"
        TOR_HANDSHAKE_OK=false
    fi
else
    TOR_HANDSHAKE_OK=false
fi

sleep 1

# Test 4: HTTP proxy functionality (if curl is available)
if [ "$HTTP_OK" = true ] && command -v curl >/dev/null 2>&1; then
    echo "🔍 Testing HTTP proxy functionality..."
    if curl -s --proxy http://$HOST:8118 --max-time 10 http://httpbin.org/ip >/dev/null 2>&1; then
        echo "✅ HTTP proxy working"
        HTTP_FUNC_OK=true
    else
        echo "⚠️  HTTP proxy not responding"
        HTTP_FUNC_OK=false
    fi
else
    HTTP_FUNC_OK=false
fi

# Summary
echo ""
echo "=============================="
echo "📊 Test Results Summary:"
echo "  SOCKS5 Port (9050): $([ "$SOCKS5_OK" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "  HTTP Port (8118): $([ "$HTTP_OK" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "  Tor Handshake: $([ "$TOR_HANDSHAKE_OK" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "  HTTP Function: $([ "$HTTP_FUNC_OK" = true ] && echo "✅ PASS" || echo "❌ FAIL")"

echo ""
echo "=============================="

# Overall assessment
if [ "$SOCKS5_OK" = true ] && [ "$HTTP_OK" = true ] && [ "$TOR_HANDSHAKE_OK" = true ]; then
    echo "🎉 SUCCESS: Tor-Proxy service is fully operational!"
    exit 0
elif [ "$SOCKS5_OK" = true ] || [ "$HTTP_OK" = true ]; then
    echo "⚠️  PARTIAL: Some proxy functionality is working"
    echo "   Check service configuration and logs"
    exit 1
else
    echo "❌ FAILED: Tor-Proxy service is not responding"
    echo "   Service may not be deployed or running"
    exit 1
fi
