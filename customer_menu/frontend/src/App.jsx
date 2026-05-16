import React, { useEffect, useRef, useState } from 'react'

const API_BASE = ''

// ── PDF receipt generator ─────────────────────────────────────────────────────
// jsPDF built-in fonts only cover Latin — use "Tk" instead of the Bengali ৳ glyph
function pdfTk(n) { return 'Tk ' + Math.round(n).toLocaleString() }

async function generateReceipt(order, info, cartItems) {
  const { jsPDF } = await import('jspdf')
  const doc = new jsPDF({ unit: 'pt', format: 'a5' })
  const W = doc.internal.pageSize.getWidth()
  let y = 44

  // ── Header ──────────────────────────────────────────────────────────────────
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(20)
  doc.setTextColor(0, 0, 0)
  doc.text(info?.restaurantName || 'Restaurant', W / 2, y, { align: 'center' }); y += 24

  if (info?.outletName) {
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(10)
    doc.setTextColor(100, 100, 100)
    doc.text(info.outletName, W / 2, y, { align: 'center' }); y += 16
  }

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(9)
  doc.setTextColor(140, 140, 140)
  doc.text(new Date().toLocaleString('en-BD'), W / 2, y, { align: 'center' }); y += 22
  doc.setTextColor(0, 0, 0)

  // ── Order number block ───────────────────────────────────────────────────────
  doc.setDrawColor(160, 31, 51)
  doc.setLineWidth(0.75)
  doc.line(30, y, W - 30, y); y += 18

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(140, 140, 140)
  doc.text('ORDER NUMBER', W / 2, y, { align: 'center' }); y += 6

  doc.setFontSize(44)
  doc.setTextColor(160, 31, 51)
  doc.text(`#${order.serialNumber}`, W / 2, y + 34, { align: 'center' }); y += 50
  doc.setTextColor(0, 0, 0)
  doc.line(30, y, W - 30, y); y += 20

  // ── Items ────────────────────────────────────────────────────────────────────
  // Column header
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(140, 140, 140)
  doc.text('ITEM', 30, y)
  doc.text('QTY', W / 2, y, { align: 'center' })
  doc.text('AMOUNT', W - 30, y, { align: 'right' })
  y += 4
  doc.setLineWidth(0.3)
  doc.setDrawColor(200, 200, 200)
  doc.line(30, y, W - 30, y); y += 12
  doc.setTextColor(0, 0, 0)

  doc.setFontSize(10)
  for (const item of cartItems) {
    doc.setFont('helvetica', 'normal')
    // Wrap long item names
    const nameLines = doc.splitTextToSize(item.name, W / 2 - 10)
    doc.text(nameLines, 30, y)
    doc.setFont('helvetica', 'normal')
    doc.setTextColor(80, 80, 80)
    doc.text(`x${item.qty}`, W / 2, y, { align: 'center' })
    doc.setFont('helvetica', 'bold')
    doc.setTextColor(0, 0, 0)
    doc.text(pdfTk(item.price * item.qty), W - 30, y, { align: 'right' })
    // Unit price hint
    if (item.qty > 1) {
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(8)
      doc.setTextColor(160, 160, 160)
      doc.text(`${pdfTk(item.price)} each`, W - 30, y + 11, { align: 'right' })
      doc.setFontSize(10)
    }
    y += nameLines.length > 1 ? nameLines.length * 13 + 6 : 20
    doc.setTextColor(0, 0, 0)
  }

  // ── Notes ────────────────────────────────────────────────────────────────────
  if (order.notes) {
    y += 4
    doc.setFont('helvetica', 'italic')
    doc.setFontSize(9)
    doc.setTextColor(120, 120, 120)
    const noteLines = doc.splitTextToSize(`Note: ${order.notes}`, W - 60)
    doc.text(noteLines, 30, y); y += noteLines.length * 13 + 4
    doc.setTextColor(0, 0, 0)
  }

  // ── Total ────────────────────────────────────────────────────────────────────
  y += 4
  doc.setLineWidth(0.75)
  doc.setDrawColor(160, 31, 51)
  doc.line(30, y, W - 30, y); y += 16
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(13)
  doc.text('Total', 30, y)
  doc.setTextColor(160, 31, 51)
  doc.text(pdfTk(order.total), W - 30, y, { align: 'right' }); y += 30
  doc.setTextColor(0, 0, 0)

  // ── Footer ───────────────────────────────────────────────────────────────────
  doc.setLineWidth(0.3)
  doc.setDrawColor(220, 220, 220)
  doc.line(30, y, W - 30, y); y += 14
  doc.setFont('helvetica', 'italic')
  doc.setFontSize(9)
  doc.setTextColor(160, 160, 160)
  doc.text('Thank you for dining with us!', W / 2, y, { align: 'center' }); y += 13
  doc.setFontSize(7)
  doc.text(`Order ID: ${order.orderId?.slice(0, 12) ?? ''}`, W / 2, y, { align: 'center' })

  doc.save(`receipt-${order.serialNumber ?? order.orderId?.slice(0, 8) ?? 'order'}.pdf`)
}

// ── Palette ───────────────────────────────────────────────────────────────────
const C = {
  bg:       '#160204',
  surface:  '#280509',
  surface2: '#3A080E',
  surface3: '#4D0C14',
  wine:     '#C8101E',
  wineRich: '#D91B28',
  wineDark: '#0D0103',
  gold:     '#C9A86C',
  goldLt:   '#E8D5A3',
  cream:    '#F5EDEA',
  text:     '#F5EDEA',
  muted:    '#C49098',
  border:   '#5C0C14',
  overlay:  'rgba(15,2,4,0.95)',
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function getOutletId() {
  const p = new URLSearchParams(window.location.search)
  if (p.get('outlet')) return p.get('outlet')
  const parts = window.location.pathname.split('/').filter(Boolean)
  const idx = parts.indexOf('menu')
  if (idx !== -1 && parts[idx + 1]) return parts[idx + 1]
  return null
}

function cartTotal(cart, items) {
  return Object.entries(cart).reduce((sum, [id, qty]) => {
    const item = items.find(i => i.id === id)
    return sum + (item ? item.price * qty : 0)
  }, 0)
}
function cartCount(cart) { return Object.values(cart).reduce((s, q) => s + q, 0) }
function taka(n) { return '৳' + Math.round(n).toLocaleString('en-BD') }

function buildMedia(item) {
  const media = []
  if (item.imageUrl) media.push({ type: 'image', url: item.imageUrl })
  if (item.videoUrl) media.push({ type: 'video', url: item.videoUrl })
  return media
}

// ── Gold divider ornament ─────────────────────────────────────────────────────
function GoldLine() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '0 auto', width: 140 }}>
      <div style={{ flex: 1, height: 1, background: `linear-gradient(to right, transparent, ${C.gold})` }} />
      <div style={{ width: 5, height: 5, borderRadius: '50%', background: C.gold, flexShrink: 0 }} />
      <div style={{ flex: 1, height: 1, background: `linear-gradient(to left, transparent, ${C.gold})` }} />
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════════════════════
export default function App() {
  const urlOutletId = getOutletId()
  const [outletId, setOutletId] = useState(urlOutletId)
  const [phase, setPhase]       = useState('loading')
  const [info, setInfo]         = useState(null)
  const [items, setItems]       = useState([])
  const [cart, setCart]         = useState({})
  const [activeCategory, setCat]= useState('All')
  const [note, setNote]         = useState('')
  const [submitting, setSub]    = useState(false)
  const [errorMsg, setErr]      = useState('')
  const [orderRef, setOrderRef] = useState(null)
  const [lightbox, setLightbox] = useState(null)
  const [lastCart, setLastCart] = useState([])

  useEffect(() => {
    async function loadMenu() {
      try {
        setPhase('loading')
        let activeOutletId = urlOutletId
        let infoRes
        if (!activeOutletId) {
          infoRes = await fetch(`${API_BASE}/customer/default`).then(r => r.json())
          if (!infoRes.ok) throw new Error('Could not load restaurant')
          activeOutletId = infoRes.data.outletId
          setOutletId(activeOutletId)
        } else {
          infoRes = await fetch(`${API_BASE}/customer/${activeOutletId}/info`).then(r => r.json())
        }
        const menuRes = await fetch(`${API_BASE}/customer/${activeOutletId}/menu`).then(r => r.json())
      if (!infoRes.ok || !menuRes.ok) throw new Error('Could not load menu')
      setInfo(infoRes.data)
      setItems(menuRes.data)
      setPhase('menu')
      } catch (e) {
        setPhase('error')
        setErr(e.message || 'Could not load menu.')
      }
    }
    loadMenu()
  }, [urlOutletId])

  const categories = ['All', ...new Set(items.map(i => i.category).filter(Boolean))]
  const visible = activeCategory === 'All' ? items : items.filter(i => i.category === activeCategory)

  function add(id) { setCart(c => ({ ...c, [id]: (c[id] || 0) + 1 })) }
  function rem(id) {
    setCart(c => {
      const n = { ...c }
      if ((n[id] || 0) <= 1) delete n[id]; else n[id]--
      return n
    })
  }

  async function placeOrder() {
    setSub(true)
    try {
      const orderItems = Object.entries(cart).map(([id, qty]) => {
        const item = items.find(i => i.id === id)
        return { menuItemId: id, name: item.name, qty, price: item.price }
      })
      const res = await fetch(`${API_BASE}/customer/${outletId}/orders`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items: orderItems, note: note || null }),
      })
      const data = await res.json()
      if (!data.ok) throw new Error(data.detail || 'Order failed')
      setLastCart(Object.entries(cart).map(([id, qty]) => {
        const item = items.find(i => i.id === id)
        return { name: item.name, qty, price: item.price }
      }))
      setOrderRef(data.data)
      setPhase('success')
    } catch (e) { alert(e.message || 'Could not place order.') }
    finally { setSub(false) }
  }

  if (phase === 'loading') return <LoadingScreen />
  if (phase === 'error')   return <ErrorScreen message={errorMsg} />
  if (phase === 'success') return (
    <SuccessScreen order={orderRef} info={info} cartItems={lastCart}
      onBack={() => { setCart({}); setLastCart([]); setPhase('menu') }} />
  )
  if (phase === 'cart') return (
    <CartScreen cart={cart} items={items} note={note} onNote={setNote}
      onAdd={add} onRemove={rem} onBack={() => setPhase('menu')}
      onPlace={placeOrder} submitting={submitting} info={info} />
  )

  return (
    <>
      <MenuScreen
        info={info} items={visible} allItems={items} cart={cart}
        categories={categories} activeCategory={activeCategory}
        onCategory={setCat} onAdd={add} onRemove={rem}
        onOpenCart={() => setPhase('cart')}
        onOpenDetail={item => setLightbox({ item })}
      />
      {lightbox && (
        <ItemDetailSheet
          item={lightbox.item}
          qty={cart[lightbox.item.id] || 0}
          onAdd={() => add(lightbox.item.id)}
          onRemove={() => rem(lightbox.item.id)}
          onClose={() => setLightbox(null)}
        />
      )}
    </>
  )
}

// ═══════════════════════════════════════════════════════════════════════════════
function LoadingScreen() {
  return (
    <div style={S.centerPage}>
      <div style={S.wineSpinner} />
      <p style={{ color: C.muted, marginTop: 20, fontWeight: 500, letterSpacing: 2, fontSize: 11, textTransform: 'uppercase' }}>
        Loading…
      </p>
    </div>
  )
}

function ErrorScreen({ message }) {
  return (
    <div style={S.centerPage}>
      <div style={{ fontSize: 42, marginBottom: 16 }}>🍷</div>
      <p style={{ color: C.gold, fontFamily: 'Cormorant Garamond, serif', fontSize: 18, textAlign: 'center', padding: '0 32px' }}>
        {message}
      </p>
    </div>
  )
}

function SuccessScreen({ order, info, cartItems, onBack }) {
  return (
    <div style={S.centerPage}>
      <div className="fade-up" style={S.successCard}>
        <div style={S.checkRing}>
          <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
            <path d="M6 16l7 7 13-13" stroke={C.gold} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </div>
        <h2 style={{ fontFamily: 'Cormorant Garamond, serif', fontSize: 30, fontWeight: 600, color: C.cream, marginTop: 20 }}>
          Order Placed
        </h2>
        <p style={{ color: C.muted, fontSize: 13, marginTop: 4 }}>অর্ডার নেওয়া হয়েছে</p>
        <GoldLine />

        {/* Serial number */}
        {order?.serialNumber != null && (
          <>
            <p style={{ color: C.muted, fontSize: 10, letterSpacing: 2, textTransform: 'uppercase', marginTop: 10 }}>
              Order Number
            </p>
            <div style={{
              fontFamily: 'Cormorant Garamond, serif',
              fontSize: 80, fontWeight: 700, color: C.gold,
              lineHeight: 1, letterSpacing: -3,
            }}>
              #{order.serialNumber}
            </div>
          </>
        )}

        {/* Total */}
        {order && (
          <div style={{ fontFamily: 'Cormorant Garamond, serif', fontSize: 28, fontWeight: 700, color: C.cream, marginTop: 6 }}>
            {taka(order.total)}
          </div>
        )}

        {info?.restaurantName && (
          <p style={{ color: C.muted, fontSize: 11, marginTop: 4, letterSpacing: 1, textTransform: 'uppercase' }}>
            {info.restaurantName}{info.outletName ? ` · ${info.outletName}` : ''}
          </p>
        )}
        <p style={{ color: C.muted, fontSize: 13, marginTop: 10, textAlign: 'center', lineHeight: 1.6 }}>
          Your order is being prepared.<br />Please wait.
        </p>
        <button style={S.btnGold} onClick={onBack}>Order Again</button>
        <button
          style={{ ...S.btnGold, background: 'transparent', border: `1px solid ${C.gold}`, color: C.gold, marginTop: 0 }}
          onClick={() => generateReceipt(order, info, cartItems)}
        >
          Download Receipt · রিসিট ডাউনলোড
        </button>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════════════════════
function MenuScreen({ info, items, allItems, cart, categories, activeCategory, onCategory, onAdd, onRemove, onOpenCart, onOpenDetail }) {
  const count = cartCount(cart)
  const total = cartTotal(cart, allItems)

  return (
    <div style={S.screen}>
      <HeroSection info={info} />

      {/* Category bar */}
      <div style={S.catBar}>
        {categories.map(cat => (
          <button key={cat}
            style={{ ...S.catChip, ...(cat === activeCategory ? S.catChipActive : {}) }}
            onClick={() => onCategory(cat)}
          >
            {cat === 'All' ? 'সব · All' : cat}
          </button>
        ))}
      </div>

      {/* Menu list */}
      <div style={{ flex: 1, paddingBottom: 100 }}>
        {items.length === 0 ? (
          <div style={{ textAlign: 'center', color: C.muted, padding: '60px 0', fontStyle: 'italic' }}>
            No items available
          </div>
        ) : (
          items.map((item, i) => (
            <MenuCard
              key={item.id}
              item={item}
              qty={cart[item.id] || 0}
              onAdd={() => onAdd(item.id)}
              onRemove={() => onRemove(item.id)}
              onOpenDetail={() => onOpenDetail(item)}
              delay={i}
            />
          ))
        )}
      </div>

      {/* Cart bar */}
      {count > 0 && (
        <div className="slide-up" style={S.cartBar} onClick={onOpenCart}>
          <div style={S.cartBadge}>{count}</div>
          <span style={S.cartPrice}>{taka(total)}</span>
        </div>
      )}
    </div>
  )
}

// ── Hero ──────────────────────────────────────────────────────────────────────
function HeroSection({ info }) {
  const videoRef = useRef(null)
  const [slide, setSlide] = useState(0)
  const touchX = useRef(null)
  const gallery = info?.galleryImages || []
  const hasVideo = !!info?.videoUrl
  const hasGallery = !hasVideo && gallery.length > 0

  // Auto-advance carousel
  useEffect(() => {
    if (!hasGallery || gallery.length < 2) return
    const id = setInterval(() => setSlide(i => (i + 1) % gallery.length), 4000)
    return () => clearInterval(id)
  }, [hasGallery, gallery.length])

  // Auto-play video
  useEffect(() => {
    if (videoRef.current) videoRef.current.play().catch(() => {})
  }, [info?.videoUrl])

  function onTouchStart(e) { touchX.current = e.touches[0].clientX }
  function onTouchEnd(e) {
    if (touchX.current === null) return
    const dx = e.changedTouches[0].clientX - touchX.current
    if (dx < -48) setSlide(i => (i + 1) % gallery.length)
    if (dx > 48)  setSlide(i => (i - 1 + gallery.length) % gallery.length)
    touchX.current = null
  }

  return (
    <div style={S.hero} onTouchStart={hasGallery ? onTouchStart : undefined} onTouchEnd={hasGallery ? onTouchEnd : undefined}>
      {/* Background: video → gallery carousel → bannerImage → gradient */}
      {hasVideo ? (
        <video ref={videoRef} src={info.videoUrl} autoPlay muted loop playsInline style={S.heroMedia} />
      ) : hasGallery ? (
        <>
          {gallery.map((url, i) => (
            <img
              key={url}
              src={url}
              alt=""
              style={{
                ...S.heroMedia,
                opacity: i === slide ? 1 : 0,
                transition: 'opacity 0.7s ease',
              }}
            />
          ))}
        </>
      ) : info?.bannerUrl ? (
        <img src={info.bannerUrl} alt="" style={S.heroMedia} />
      ) : (
        <div style={S.heroGradient} />
      )}

      {/* Vignette overlay */}
      <div style={S.heroOverlay} />

      {/* Decorative rings */}
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', overflow: 'hidden' }}>
        <div style={S.heroRing1} />
        <div style={S.heroRing2} />
      </div>

      {/* Content */}
      <div style={S.heroContent}>
        <div style={S.heroBrandMark}>
          {info?.restaurantName?.[0]?.toUpperCase() || 'R'}
        </div>
        <h1 style={S.heroTitle}>
          {info?.restaurantName || 'Our Menu'}
        </h1>
        {info?.outletName && (
          <p style={S.heroSub}>{info.outletName}</p>
        )}
        <GoldLine />

        {/* Carousel dots */}
        {hasGallery && gallery.length > 1 && (
          <div style={{ display: 'flex', gap: 6, marginTop: 4 }}>
            {gallery.map((_, i) => (
              <div
                key={i}
                onClick={() => setSlide(i)}
                style={{
                  width: i === slide ? 18 : 6,
                  height: 6,
                  borderRadius: 3,
                  background: i === slide ? C.gold : 'rgba(201,168,108,0.35)',
                  transition: 'all 0.3s',
                  cursor: 'pointer',
                }}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

// ── Menu Card ─────────────────────────────────────────────────────────────────
function MenuCard({ item, qty, onAdd, onRemove, onOpenDetail, delay }) {
  const hasMedia = !!(item.imageUrl || item.videoUrl)

  return (
    <div className="fade-up"
      style={{ ...S.card, animationDelay: `${Math.min(delay * 0.04, 0.3)}s` }}
      onClick={onOpenDetail}
    >
      {/* Image thumbnail */}
      {hasMedia && (
        <div style={S.cardImgWrap}>
          <img
            src={item.imageUrl}
            alt={item.name}
            style={S.cardImg}
            onError={e => { e.target.parentElement.style.display = 'none' }}
          />
          {item.videoUrl && (
            <div style={S.playBadge}>
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <polygon points="3,1 13,7 3,13" fill={C.gold}/>
              </svg>
            </div>
          )}
        </div>
      )}

      {/* Info */}
      <div style={S.cardBody}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={S.cardName}>{item.name}</div>
          <div style={S.cardPrice}>{taka(item.price)}</div>
        </div>

        {/* Quantity control — stop propagation so card tap doesn't open detail */}
        <div style={{ flexShrink: 0, WebkitTapHighlightColor: 'transparent' }} onClick={e => e.stopPropagation()}>
          {qty === 0 ? (
            <button style={S.addBtn} onClick={onAdd}>
              <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                <path d="M8 2v12M2 8h12" stroke={C.bg} strokeWidth="2" strokeLinecap="round"/>
              </svg>
            </button>
          ) : (
            <div style={S.qtyRow}>
              <button style={S.qtyBtn} onClick={onRemove}>−</button>
              <span style={S.qtyNum}>{qty}</span>
              <button style={S.qtyBtn} onClick={onAdd}>+</button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Item Detail Sheet ─────────────────────────────────────────────────────────
function ItemDetailSheet({ item, qty, onAdd, onRemove, onClose }) {
  const media = buildMedia(item)
  const videoRef = useRef(null)

  useEffect(() => {
    if (videoRef.current) videoRef.current.play().catch(() => {})
  }, [item.id])

  useEffect(() => {
    function onKey(e) { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const current = media[0]

  return (
    <div className="fade-in" style={S.lbOverlay} onClick={e => { if (e.target === e.currentTarget) onClose() }}>
      <div className="slide-up" style={S.lbSheet}>

        {/* Close */}
        <button style={S.lbClose} onClick={onClose}>
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            <path d="M2 2l14 14M16 2L2 16" stroke={C.cream} strokeWidth="2" strokeLinecap="round"/>
          </svg>
        </button>

        {/* Media stage */}
        <div style={S.lbStage}>
          {media.length === 0 ? (
            <div style={S.lbNoMedia}><div style={{ fontSize: 40 }}>🍽️</div></div>
          ) : current?.type === 'video' ? (
            <video
              ref={videoRef}
              key={current.url}
              src={current.url}
              controls
              autoPlay
              muted
              playsInline
              style={S.lbVideo}
            />
          ) : (
            <img src={current?.url} alt={item.name} style={S.lbImage} />
          )}
        </div>

        {/* Item detail */}
        <div style={{ ...S.lbDetail, flex: 1, overflowY: 'auto' }}>
          <div style={S.lbItemName}>{item.name}</div>
          {item.description && <div style={S.lbItemDesc}>{item.description}</div>}
          <div style={S.lbItemPrice}>{taka(item.price)}</div>
        </div>

        {/* Footer: add to cart */}
        <div style={S.lbFooter}>
          {qty === 0 ? (
            <button style={S.btnGold} onClick={onAdd}>
              Add to Order · অর্ডারে যোগ করুন
            </button>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', gap: 16, justifyContent: 'center' }}>
              <button style={{ ...S.qtyBtn, width: 44, height: 44, fontSize: 20, borderRadius: 10 }} onClick={onRemove}>−</button>
              <span style={{ ...S.qtyNum, fontSize: 20, minWidth: 32 }}>{qty}</span>
              <button style={{ ...S.qtyBtn, width: 44, height: 44, fontSize: 20, borderRadius: 10 }} onClick={onAdd}>+</button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════════════════════
function CartScreen({ cart, items, note, onNote, onAdd, onRemove, onBack, onPlace, submitting, info }) {
  const cartItems = Object.entries(cart)
    .map(([id, qty]) => ({ ...items.find(i => i.id === id), qty }))
    .filter(Boolean)
  const total = cartTotal(cart, items)

  return (
    <div style={S.screen}>
      {/* Header */}
      <div style={S.cartHeader}>
        <button style={S.backBtn} onClick={onBack}>
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
            <path d="M13 4L7 10l6 6" stroke={C.cream} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
        <div>
          <h2 style={{ fontFamily: 'Cormorant Garamond, serif', fontSize: 24, fontWeight: 600, color: C.cream }}>
            Your Order
          </h2>
          {info?.restaurantName && (
            <p style={{ color: C.muted, fontSize: 11, letterSpacing: 1, textTransform: 'uppercase', marginTop: 2 }}>
              {info.restaurantName}
            </p>
          )}
        </div>
      </div>

      {/* Items */}
      <div style={{ flex: 1, paddingBottom: 160, overflowY: 'auto' }}>
        {cartItems.map((item, i) => (
          <div key={item.id} className="fade-up"
            style={{ ...S.cartItem, animationDelay: `${i * 0.05}s` }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={S.cartItemName}>{item.name}</div>
              <div style={{ color: C.muted, fontSize: 12, marginTop: 2 }}>{taka(item.price)} each</div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexShrink: 0 }}>
              <div style={S.qtyRow}>
                <button style={S.qtyBtn} onClick={() => onRemove(item.id)}>−</button>
                <span style={S.qtyNum}>{item.qty}</span>
                <button style={S.qtyBtn} onClick={() => onAdd(item.id)}>+</button>
              </div>
              <div style={{ color: C.gold, fontWeight: 700, fontSize: 14, minWidth: 60, textAlign: 'right' }}>
                {taka(item.price * item.qty)}
              </div>
            </div>
          </div>
        ))}

        {/* Separator */}
        <div style={{ height: 1, background: C.border, margin: '16px 20px' }} />

        {/* Note */}
        <div style={{ padding: '0 20px' }}>
          <label style={{ display: 'block', color: C.muted, fontSize: 11, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 8 }}>
            Special Instructions
          </label>
          <textarea
            style={S.noteInput}
            placeholder="e.g. no onion, extra spicy · বিশেষ নির্দেশনা"
            value={note}
            onChange={e => onNote(e.target.value)}
            rows={3}
          />
        </div>
      </div>

      {/* Footer */}
      <div style={S.cartFooter}>
        <div style={S.dividerLine} />
        <div style={S.totalRow}>
          <span style={{ color: C.muted, fontSize: 13, fontWeight: 500 }}>Total · মোট</span>
          <span style={{ fontFamily: 'Cormorant Garamond, serif', fontSize: 28, fontWeight: 700, color: C.gold }}>
            {taka(total)}
          </span>
        </div>
        <button style={{ ...S.btnGold, opacity: submitting ? 0.7 : 1 }}
          disabled={submitting} onClick={onPlace}>
          {submitting ? 'Placing Order…' : 'Place Order · অর্ডার করুন'}
        </button>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════════════════════
// Styles
const S = {
  // Layout
  screen:    { minHeight: '100vh', background: C.bg, display: 'flex', flexDirection: 'column' },
  centerPage:{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', background: C.bg, padding: 24 },

  // Loading spinner
  wineSpinner: {
    width: 40, height: 40,
    border: `2px solid ${C.surface3}`,
    borderTop: `2px solid ${C.gold}`,
    borderRadius: '50%',
    animation: 'spin .9s linear infinite',
  },

  // Hero
  hero: { position: 'relative', height: 260, overflow: 'hidden', flexShrink: 0 },
  heroMedia: { position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' },
  heroGradient: {
    position: 'absolute', inset: 0,
    background: `radial-gradient(ellipse at 30% 40%, ${C.wineRich}66 0%, ${C.wineDark}90 45%, ${C.bg} 100%)`,
  },
  heroOverlay: {
    position: 'absolute', inset: 0,
    background: 'linear-gradient(to bottom, rgba(8,1,2,.25) 0%, rgba(8,1,2,.5) 60%, rgba(8,1,2,.95) 100%)',
  },
  heroRing1: {
    position: 'absolute', width: 340, height: 340, borderRadius: '50%',
    border: `1px solid rgba(201,168,108,.08)`,
    top: -120, right: -80,
  },
  heroRing2: {
    position: 'absolute', width: 220, height: 220, borderRadius: '50%',
    border: `1px solid rgba(201,168,108,.06)`,
    bottom: -60, left: -40,
  },
  heroContent: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    padding: '0 24px 24px',
    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
  },
  heroBrandMark: {
    width: 52, height: 52, borderRadius: '50%',
    border: `2px solid ${C.gold}`,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontFamily: 'Cormorant Garamond, serif',
    fontSize: 24, fontWeight: 700, color: C.gold,
    background: 'rgba(8,1,2,.65)',
    marginBottom: 4,
  },
  heroTitle: {
    fontFamily: 'Cormorant Garamond, serif',
    fontSize: 32, fontWeight: 600, fontStyle: 'italic',
    color: C.cream, textAlign: 'center', lineHeight: 1.1,
    textShadow: '0 2px 12px rgba(0,0,0,.6)',
  },
  heroSub: {
    color: C.muted, fontSize: 11, letterSpacing: 2,
    textTransform: 'uppercase', textAlign: 'center',
  },

  // Category bar
  catBar: {
    display: 'flex', gap: 8, padding: '12px 16px',
    overflowX: 'auto', scrollbarWidth: 'none',
    background: C.surface, borderBottom: `1px solid ${C.border}`,
    flexShrink: 0,
  },
  catChip: {
    flexShrink: 0, padding: '6px 16px', borderRadius: 999,
    border: `1px solid ${C.border}`, background: 'transparent',
    fontSize: 12, fontWeight: 600, color: C.muted,
    cursor: 'pointer', whiteSpace: 'nowrap',
    fontFamily: 'DM Sans, sans-serif',
    transition: 'all .15s',
  },
  catChipActive: {
    background: C.wine, color: C.goldLt, borderColor: C.wine,
  },

  // Menu card
  card: {
    display: 'flex', alignItems: 'center', gap: 10,
    padding: '10px 14px',
    borderBottom: `1px solid ${C.border}`,
    background: C.bg,
    cursor: 'pointer',
  },
  cardImgWrap: {
    position: 'relative', width: 54, height: 54,
    borderRadius: 8, overflow: 'hidden', flexShrink: 0,
    border: `1px solid ${C.border}`,
  },
  cardImg: {
    width: '100%', height: '100%', objectFit: 'cover',
    display: 'block',
  },
  playBadge: {
    position: 'absolute', top: 6, right: 6,
    width: 24, height: 24, borderRadius: '50%',
    background: 'rgba(13,6,8,.75)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  },
  cardBody: { flex: 1, display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 },
  cardName: {
    fontFamily: 'Cormorant Garamond, serif',
    fontSize: 15, fontWeight: 600, color: C.cream,
    lineHeight: 1.25, marginBottom: 2,
  },
  cardPrice: {
    fontFamily: 'Cormorant Garamond, serif',
    fontSize: 14, fontWeight: 700, color: C.gold,
  },

  // Qty controls
  addBtn: {
    width: 32, height: 32, borderRadius: 8,
    background: C.gold, border: 'none',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    cursor: 'pointer', flexShrink: 0,
    WebkitTapHighlightColor: 'transparent',
  },
  qtyRow: { display: 'flex', alignItems: 'center', gap: 6 },
  qtyBtn: {
    width: 26, height: 26, borderRadius: 7,
    background: C.surface2, border: `1px solid ${C.border}`,
    fontSize: 15, fontWeight: 600, color: C.cream,
    cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontFamily: 'DM Sans, sans-serif',
    WebkitTapHighlightColor: 'transparent',
  },
  qtyNum: { fontWeight: 700, fontSize: 13, color: C.cream, minWidth: 18, textAlign: 'center' },

  // Cart FAB (bottom-right pill)
  cartBar: {
    position: 'fixed', bottom: 24, right: 20,
    background: `linear-gradient(135deg, ${C.wineRich}, #8B0A12)`,
    borderRadius: 999, padding: '10px 16px 10px 10px',
    display: 'flex', alignItems: 'center', gap: 8,
    cursor: 'pointer', zIndex: 20,
    border: `1px solid rgba(201,168,108,.25)`,
    boxShadow: '0 6px 28px rgba(0,0,0,.6)',
    WebkitTapHighlightColor: 'transparent',
  },
  cartBadge: {
    background: C.gold, color: C.bg,
    fontWeight: 800, fontSize: 12,
    width: 28, height: 28, borderRadius: '50%',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    flexShrink: 0,
  },
  cartPrice: {
    fontFamily: 'Cormorant Garamond, serif',
    color: C.gold, fontWeight: 700, fontSize: 16,
  },

  // Lightbox
  lbOverlay: {
    position: 'fixed', inset: 0, zIndex: 50,
    background: 'rgba(8,2,5,.9)',
    display: 'flex', alignItems: 'flex-end',
    backdropFilter: 'blur(4px)',
  },
  lbSheet: {
    width: '100%', maxHeight: '92vh',
    background: C.surface,
    borderRadius: '20px 20px 0 0',
    overflow: 'hidden',
    display: 'flex', flexDirection: 'column',
    border: `1px solid ${C.border}`,
    borderBottom: 'none',
  },
  lbClose: {
    position: 'absolute', top: 16, right: 16, zIndex: 5,
    width: 36, height: 36, borderRadius: '50%',
    background: 'rgba(13,6,8,.7)',
    border: `1px solid ${C.border}`,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    cursor: 'pointer',
  },
  lbStage: {
    position: 'relative',
    width: '100%', aspectRatio: '16/9',
    background: C.bg,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    overflow: 'hidden', flexShrink: 0,
  },
  lbImage: { width: '100%', height: '100%', objectFit: 'contain' },
  lbVideo: { width: '100%', height: '100%', objectFit: 'contain', background: '#000' },
  lbNoMedia: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' },
  lbArrow: {
    position: 'absolute', top: '50%', transform: 'translateY(-50%)',
    width: 36, height: 36, borderRadius: '50%',
    background: 'rgba(13,6,8,.7)', border: `1px solid ${C.border}`,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    cursor: 'pointer', zIndex: 3,
  },
  lbDots: { display: 'flex', justifyContent: 'center', gap: 6, padding: '10px 0 4px' },
  lbDot: {
    width: 6, height: 6, borderRadius: '50%',
    background: C.border, border: 'none', cursor: 'pointer', padding: 0,
  },
  lbDotActive: { background: C.gold, width: 18, borderRadius: 3 },
  lbDetail: {
    padding: '16px 20px 28px',
    borderTop: `1px solid ${C.border}`,
    overflowY: 'auto',
  },
  lbItemName: {
    fontFamily: 'Cormorant Garamond, serif',
    fontSize: 24, fontWeight: 600, color: C.cream, marginBottom: 6,
  },
  lbItemDesc: { fontSize: 13, color: C.muted, lineHeight: 1.6, marginBottom: 10 },
  lbItemPrice: {
    fontFamily: 'Cormorant Garamond, serif',
    fontSize: 22, fontWeight: 700, color: C.gold,
  },
  lbFooter: {
    padding: '12px 20px 28px',
    borderTop: `1px solid ${C.border}`,
    background: C.surface,
    flexShrink: 0,
  },

  // Cart screen
  cartHeader: {
    background: C.surface,
    padding: '16px 20px',
    borderBottom: `1px solid ${C.border}`,
    display: 'flex', alignItems: 'center', gap: 14,
    position: 'sticky', top: 0, zIndex: 10,
    flexShrink: 0,
  },
  backBtn: {
    width: 36, height: 36, borderRadius: 10,
    background: C.surface2, border: `1px solid ${C.border}`,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    cursor: 'pointer', flexShrink: 0,
  },
  cartItem: {
    display: 'flex', alignItems: 'center',
    padding: '14px 20px', borderBottom: `1px solid ${C.border}`,
    gap: 12,
  },
  cartItemName: {
    fontFamily: 'Cormorant Garamond, serif',
    fontSize: 16, fontWeight: 600, color: C.cream,
  },
  noteInput: {
    width: '100%', padding: '12px 14px',
    borderRadius: 10,
    border: `1px solid ${C.border}`,
    background: C.surface2,
    color: C.cream,
    fontSize: 13, fontFamily: 'DM Sans, sans-serif',
    resize: 'none', outline: 'none',
    '::placeholder': { color: C.muted },
  },
  cartFooter: {
    position: 'fixed', bottom: 0, left: 0, right: 0,
    background: C.surface,
    borderTop: `1px solid ${C.border}`,
    padding: '16px 20px 28px',
  },
  dividerLine: { height: 1, background: C.border, marginBottom: 14 },
  totalRow: {
    display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14,
  },

  // Buttons
  btnGold: {
    width: '100%', padding: '15px 0',
    background: `linear-gradient(135deg, ${C.gold}, #B08040)`,
    border: 'none', borderRadius: 12,
    fontFamily: 'DM Sans, sans-serif',
    fontWeight: 700, fontSize: 15, color: C.bg,
    cursor: 'pointer',
    letterSpacing: .3,
  },

  // Success
  successCard: {
    background: C.surface,
    borderRadius: 20,
    padding: '36px 28px',
    textAlign: 'center',
    maxWidth: 340, width: '100%',
    border: `1px solid ${C.border}`,
    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10,
  },
  checkRing: {
    width: 72, height: 72, borderRadius: '50%',
    border: `2px solid ${C.gold}`,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    background: 'rgba(201,168,108,.08)',
  },
}
