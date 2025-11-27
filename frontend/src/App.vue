<script setup lang="ts">
import { ref, computed, onBeforeUnmount, nextTick } from 'vue'

// ============== 常數定義 ==============
const MIN_DENSITY_THRESHOLD = 0.001
const VIDEO_DETECTION_INTERVAL_MS = 500

interface BoundingBox {
  x1: number
  y1: number
  x2: number
  y2: number
  confidence: number
}

interface DetectionResult {
  person_count: number
  density: number
  status: string
  bounding_boxes: BoundingBox[]
  image_width: number
  image_height: number
}

// ============== 側邊欄：監控參數設定 ==============
const useRoi = ref(false)
const roiX0 = ref(0)
const roiY0 = ref(0)
const roiX1 = ref(100)
const roiY1 = ref(100)
const areaM2 = ref(20.0)
const densityWarn = ref(5.0)
const densityDanger = ref(6.5)
const holdSeconds = ref(5)
const sidebarOpen = ref(true)

// ============== 輸入來源選擇 ==============
type InputSource = 'image' | 'video' | 'url' | 'camera'
const inputSource = ref<InputSource>('image')

// ============== 基本狀態 ==============
const videoRef = ref<HTMLVideoElement | null>(null)
const canvasRef = ref<HTMLCanvasElement | null>(null)
const uploadVideoRef = ref<HTMLVideoElement | null>(null)
const personCount = ref(0)
const density = ref(0)
const status = ref('normal')
const isStreaming = ref(false)
const lastUpdate = ref<Date | null>(null)
const apiUrl = ref(import.meta.env.VITE_API_URL || 'http://localhost:8001')
const fileInputRef = ref<HTMLInputElement | null>(null)
const videoFileInputRef = ref<HTMLInputElement | null>(null)
const uploadedImageUrl = ref<string | null>(null)
const isUploading = ref(false)
const videoUrl = ref('')
const isPlayingVideo = ref(false)
const uploadedVideoUrl = ref<string | null>(null)

// ============== 連續超標警報追蹤 ==============
const overThresholdStart = ref<number | null>(null)
const secondsOverThreshold = ref(0)
const showAlert = ref(false)

let streamInterval: number | null = null
let videoDetectionInterval: number | null = null

// ============== 計算屬性 ==============
const densityRatio = computed(() => {
  return Math.min(density.value / Math.max(densityDanger.value, MIN_DENSITY_THRESHOLD), 1.0)
})

const densityBarColor = computed(() => {
  if (status.value === 'danger') return 'bg-red-500'
  if (status.value === 'warning') return 'bg-orange-500'
  return 'bg-green-500'
})

// ============== 構建 FormData ==============
const buildFormData = (blob: Blob | File, filename: string): FormData => {
  const formData = new FormData()
  formData.append('file', blob, filename)
  formData.append('roi_area_m2', areaM2.value.toString())
  formData.append('density_warn', densityWarn.value.toString())
  formData.append('density_danger', densityDanger.value.toString())
  
  if (useRoi.value) {
    formData.append('roi_x0', roiX0.value.toString())
    formData.append('roi_y0', roiY0.value.toString())
    formData.append('roi_x1', roiX1.value.toString())
    formData.append('roi_y1', roiY1.value.toString())
  }
  
  return formData
}

// ============== 更新超標時間追蹤 ==============
const updateOverThresholdTracking = () => {
  if (status.value !== 'normal') {
    if (overThresholdStart.value === null) {
      overThresholdStart.value = Date.now()
    }
    secondsOverThreshold.value = (Date.now() - overThresholdStart.value) / 1000
    
    if (secondsOverThreshold.value >= holdSeconds.value) {
      showAlert.value = true
    }
  } else {
    overThresholdStart.value = null
    secondsOverThreshold.value = 0
    showAlert.value = false
  }
}

// ============== 開始視訊串流 (拍照) ==============
const startStream = async () => {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { width: 1280, height: 720 }
    })
    
    if (videoRef.value) {
      videoRef.value.srcObject = stream
      videoRef.value.play()
      isStreaming.value = true
      uploadedImageUrl.value = null
      uploadedVideoUrl.value = null
      startDetection()
    }
  } catch (error) {
    console.error('無法存取攝影機:', error)
    alert('無法存取攝影機,請確認權限設定')
  }
}

// ============== 停止視訊串流 ==============
const stopStream = () => {
  if (videoRef.value && videoRef.value.srcObject) {
    const tracks = (videoRef.value.srcObject as MediaStream).getTracks()
    tracks.forEach(track => track.stop())
    videoRef.value.srcObject = null
  }
  
  if (streamInterval) {
    clearInterval(streamInterval)
    streamInterval = null
  }
  
  isStreaming.value = false
  resetState()
}

// ============== 重置狀態 ==============
const resetState = () => {
  personCount.value = 0
  density.value = 0
  status.value = 'normal'
  overThresholdStart.value = null
  secondsOverThreshold.value = 0
  showAlert.value = false
}

// ============== 開始偵測 (每 2000ms) ==============
const startDetection = () => {
  if (streamInterval) {
    clearInterval(streamInterval)
  }
  
  streamInterval = window.setInterval(() => {
    captureAndDetect()
  }, 2000)
}

// ============== 擷取並偵測 ==============
const captureAndDetect = async () => {
  if (!videoRef.value || !canvasRef.value) return
  
  const canvas = canvasRef.value
  const video = videoRef.value
  const ctx = canvas.getContext('2d')
  
  if (!ctx) return
  
  canvas.width = video.videoWidth
  canvas.height = video.videoHeight
  
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
  
  canvas.toBlob(async (blob) => {
    if (!blob) return
    
    try {
      const formData = buildFormData(blob, 'frame.jpg')
      
      const response = await fetch(`${apiUrl.value}/api/detect`, {
        method: 'POST',
        body: formData
      })
      
      if (response.ok) {
        const result: DetectionResult = await response.json()
        personCount.value = result.person_count
        density.value = result.density
        status.value = result.status
        lastUpdate.value = new Date()
        
        updateOverThresholdTracking()
        drawResults(ctx, result)
      }
    } catch (error) {
      console.error('偵測失敗:', error)
    }
  }, 'image/jpeg', 0.8)
}

// ============== 繪製偵測結果 ==============
const drawResults = (ctx: CanvasRenderingContext2D, result: DetectionResult) => {
  // 繪製 ROI 區域框
  if (useRoi.value) {
    const canvas = ctx.canvas
    const x0 = (canvas.width * roiX0.value) / 100
    const y0 = (canvas.height * roiY0.value) / 100
    const x1 = (canvas.width * roiX1.value) / 100
    const y1 = (canvas.height * roiY1.value) / 100
    
    ctx.strokeStyle = '#B4B4B4'
    ctx.lineWidth = 2
    ctx.strokeRect(x0, y0, x1 - x0, y1 - y0)
  }
  
  // 繪製人員邊界框
  result.bounding_boxes.forEach(box => {
    ctx.strokeStyle = '#3CFF64'
    ctx.lineWidth = 2
    ctx.strokeRect(box.x1, box.y1, box.x2 - box.x1, box.y2 - box.y1)
  })
  
  const color = status.value === 'danger' ? '#FF3C3C' : 
                status.value === 'warning' ? '#FFA500' : '#3CFF64'
  
  // 頂部資訊面板
  ctx.fillStyle = 'rgba(0, 0, 0, 0.7)'
  ctx.fillRect(10, 10, 360, 130)
  
  ctx.fillStyle = color
  ctx.font = 'bold 24px Arial'
  ctx.fillText(`密度: ${density.value.toFixed(2)} 人/㎡ [${getStatusText()}]`, 20, 45)
  
  ctx.fillStyle = '#FFFFFF'
  ctx.font = '18px Arial'
  ctx.fillText(`人數: ${personCount.value}`, 20, 75)
  
  // 超標時間顯示
  if (secondsOverThreshold.value > 0) {
    ctx.fillStyle = color
    ctx.fillText(`超標時間: ${secondsOverThreshold.value.toFixed(1)}s`, 20, 100)
  }
  
  // 密度條
  const barX = 20
  const barY = 115
  const barW = 320
  const barH = 20
  
  ctx.strokeStyle = '#CCCCCC'
  ctx.lineWidth = 2
  ctx.strokeRect(barX, barY, barW, barH)
  
  ctx.fillStyle = color
  ctx.fillRect(barX, barY, barW * densityRatio.value, barH)
  
  // 警報顯示
  if (showAlert.value) {
    ctx.fillStyle = 'rgba(255, 0, 0, 0.8)'
    ctx.fillRect(10, 150, 340, 50)
    ctx.fillStyle = '#FFFFFF'
    ctx.font = 'bold 28px Arial'
    ctx.fillText('⚠️ ALERT: CROWD RISK!', 30, 185)
  }
}

// ============== 處理圖片上傳 ==============
const handleFileUpload = (event: Event) => {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  
  if (file && file.type.startsWith('image/')) {
    uploadAndDetect(file)
  }
}

// ============== 上傳並偵測圖片 ==============
const uploadAndDetect = async (file: File) => {
  if (!canvasRef.value) return
  
  isUploading.value = true
  
  try {
    if (isStreaming.value) {
      stopStream()
    }
    stopVideoPlayback()
    
    const reader = new FileReader()
    reader.onload = async (e) => {
      const img = new Image()
      img.onload = async () => {
        const canvas = canvasRef.value!
        const ctx = canvas.getContext('2d')!
        
        canvas.width = img.width
        canvas.height = img.height
        
        ctx.drawImage(img, 0, 0)
        
        const formData = buildFormData(file, file.name)
        
        const response = await fetch(`${apiUrl.value}/api/detect`, {
          method: 'POST',
          body: formData
        })
        
        if (response.ok) {
          const result: DetectionResult = await response.json()
          personCount.value = result.person_count
          density.value = result.density
          status.value = result.status
          lastUpdate.value = new Date()
          
          drawResults(ctx, result)
        } else {
          alert('偵測失敗，請稍後再試')
        }
        
        isUploading.value = false
      }
      img.src = e.target?.result as string
      uploadedImageUrl.value = e.target?.result as string
    }
    reader.readAsDataURL(file)
    
  } catch (error) {
    console.error('上傳失敗:', error)
    alert('上傳失敗，請稍後再試')
    isUploading.value = false
  }
}

// ============== 處理影片上傳 ==============
const handleVideoUpload = (event: Event) => {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  
  if (file && file.type.startsWith('video/')) {
    processVideoFile(file)
  }
}

// ============== 處理影片檔案 ==============
const processVideoFile = async (file: File) => {
  if (isStreaming.value) {
    stopStream()
  }
  stopVideoPlayback()
  
  uploadedVideoUrl.value = URL.createObjectURL(file)
  uploadedImageUrl.value = null
  
  // 等待 DOM 更新後播放影片
  nextTick(() => {
    startVideoPlayback()
  })
}

// ============== 載入影片連結 ==============
const loadVideoUrl = () => {
  if (!videoUrl.value) {
    alert('請輸入影片連結（支援 mp4/avi/mov 格式的直連網址）')
    return
  }
  
  if (isStreaming.value) {
    stopStream()
  }
  stopVideoPlayback()
  
  uploadedVideoUrl.value = videoUrl.value
  uploadedImageUrl.value = null
  
  nextTick(() => {
    startVideoPlayback()
  })
}

// ============== 開始影片播放與偵測 ==============
const startVideoPlayback = () => {
  if (!uploadVideoRef.value || !canvasRef.value) return
  
  const video = uploadVideoRef.value
  
  video.onloadeddata = () => {
    isPlayingVideo.value = true
    video.play()
    startVideoDetection()
  }
  
  video.onerror = () => {
    alert('無法載入影片。請確認：\n1. 連結為有效的直連網址（mp4/avi/mov）\n2. 影片為公開可存取\n3. 伺服器允許跨域存取（CORS）')
    uploadedVideoUrl.value = null
  }
  
  video.onended = () => {
    stopVideoPlayback()
  }
  
  video.load()
}

// ============== 開始影片偵測 ==============
const startVideoDetection = () => {
  if (videoDetectionInterval) {
    clearInterval(videoDetectionInterval)
  }
  
  videoDetectionInterval = window.setInterval(() => {
    captureVideoFrame()
  }, VIDEO_DETECTION_INTERVAL_MS)
}

// ============== 擷取影片幀並偵測 ==============
const captureVideoFrame = async () => {
  if (!uploadVideoRef.value || !canvasRef.value) return
  
  const video = uploadVideoRef.value
  const canvas = canvasRef.value
  const ctx = canvas.getContext('2d')
  
  if (!ctx || video.paused || video.ended) return
  
  canvas.width = video.videoWidth
  canvas.height = video.videoHeight
  
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
  
  canvas.toBlob(async (blob) => {
    if (!blob) return
    
    try {
      const formData = buildFormData(blob, 'frame.jpg')
      
      const response = await fetch(`${apiUrl.value}/api/detect`, {
        method: 'POST',
        body: formData
      })
      
      if (response.ok) {
        const result: DetectionResult = await response.json()
        personCount.value = result.person_count
        density.value = result.density
        status.value = result.status
        lastUpdate.value = new Date()
        
        updateOverThresholdTracking()
        drawResults(ctx, result)
      }
    } catch (error) {
      console.error('偵測失敗:', error)
    }
  }, 'image/jpeg', 0.8)
}

// ============== 停止影片播放 ==============
const stopVideoPlayback = () => {
  if (videoDetectionInterval) {
    clearInterval(videoDetectionInterval)
    videoDetectionInterval = null
  }
  
  if (uploadVideoRef.value) {
    uploadVideoRef.value.pause()
    uploadVideoRef.value.currentTime = 0
  }
  
  isPlayingVideo.value = false
  resetState()
}

// ============== 觸發檔案選擇 ==============
const triggerFileInput = () => {
  fileInputRef.value?.click()
}

const triggerVideoInput = () => {
  videoFileInputRef.value?.click()
}

// ============== 清除上傳的內容 ==============
const clearUpload = () => {
  uploadedImageUrl.value = null
  uploadedVideoUrl.value = null
  videoUrl.value = ''
  resetState()
  
  if (canvasRef.value) {
    const ctx = canvasRef.value.getContext('2d')
    ctx?.clearRect(0, 0, canvasRef.value.width, canvasRef.value.height)
  }
  
  stopVideoPlayback()
}

// ============== 取得狀態文字 ==============
const getStatusText = () => {
  switch (status.value) {
    case 'danger': return '危險'
    case 'warning': return '警告'
    default: return '正常'
  }
}

// ============== 切換側邊欄 ==============
const toggleSidebar = () => {
  sidebarOpen.value = !sidebarOpen.value
}

onBeforeUnmount(() => {
  stopStream()
  stopVideoPlayback()
})
</script>

<template>
  <div class="min-h-screen flex bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
    <!-- Sidebar Toggle Button (Mobile) -->
    <button 
      @click="toggleSidebar"
      class="fixed top-4 left-4 z-50 lg:hidden p-2 bg-purple-600 text-white rounded-lg shadow-lg"
    >
      {{ sidebarOpen ? '✕' : '☰' }}
    </button>

    <!-- Sidebar -->
    <aside 
      :class="[
        'fixed lg:relative z-40 w-80 h-screen bg-gray-900/95 backdrop-blur-xl border-r border-purple-500/30 overflow-y-auto transition-transform duration-300',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
      ]"
    >
      <div class="p-6 space-y-6">
        <h2 class="text-xl font-bold text-white flex items-center gap-2">
          🧭 區域與門檻設定
        </h2>

        <!-- ROI 設定 -->
        <div class="space-y-4">
          <div class="flex items-center gap-2">
            <input 
              type="checkbox" 
              v-model="useRoi" 
              id="useRoi"
              class="w-4 h-4 accent-purple-500"
            />
            <label for="useRoi" class="text-purple-200">啟用 ROI（百分比裁切）</label>
          </div>
          
          <div v-if="useRoi" class="grid grid-cols-2 gap-4 p-4 bg-gray-800/50 rounded-lg">
            <div>
              <label class="block text-purple-200 text-sm mb-1">ROI 左 (%)</label>
              <input 
                type="range" 
                v-model.number="roiX0" 
                min="0" 
                max="90" 
                class="w-full accent-purple-500"
              />
              <div class="text-white text-center">{{ roiX0 }}%</div>
            </div>
            <div>
              <label class="block text-purple-200 text-sm mb-1">ROI 上 (%)</label>
              <input 
                type="range" 
                v-model.number="roiY0" 
                min="0" 
                max="90" 
                class="w-full accent-purple-500"
              />
              <div class="text-white text-center">{{ roiY0 }}%</div>
            </div>
            <div>
              <label class="block text-purple-200 text-sm mb-1">ROI 右 (%)</label>
              <input 
                type="range" 
                v-model.number="roiX1" 
                min="10" 
                max="100" 
                class="w-full accent-purple-500"
              />
              <div class="text-white text-center">{{ roiX1 }}%</div>
            </div>
            <div>
              <label class="block text-purple-200 text-sm mb-1">ROI 下 (%)</label>
              <input 
                type="range" 
                v-model.number="roiY1" 
                min="10" 
                max="100" 
                class="w-full accent-purple-500"
              />
              <div class="text-white text-center">{{ roiY1 }}%</div>
            </div>
          </div>
        </div>

        <!-- 區域面積 -->
        <div>
          <label class="block text-purple-200 text-sm mb-2">監控區域實際面積 (㎡)</label>
          <input 
            type="number" 
            v-model.number="areaM2" 
            min="1" 
            step="1"
            class="w-full px-3 py-2 bg-gray-800 border border-purple-500/30 rounded-lg text-white focus:outline-none focus:border-purple-500"
          />
        </div>

        <!-- 警告門檻 -->
        <div>
          <label class="block text-purple-200 text-sm mb-2">警告門檻 (人/㎡)</label>
          <input 
            type="number" 
            v-model.number="densityWarn" 
            min="0.5" 
            step="0.5"
            class="w-full px-3 py-2 bg-gray-800 border border-yellow-500/30 rounded-lg text-white focus:outline-none focus:border-yellow-500"
          />
        </div>

        <!-- 危險門檻 -->
        <div>
          <label class="block text-purple-200 text-sm mb-2">危險門檻 (人/㎡)</label>
          <input 
            type="number" 
            v-model.number="densityDanger" 
            min="1" 
            step="0.5"
            class="w-full px-3 py-2 bg-gray-800 border border-red-500/30 rounded-lg text-white focus:outline-none focus:border-red-500"
          />
        </div>

        <!-- 連續超標秒數 -->
        <div>
          <label class="block text-purple-200 text-sm mb-2">連續超標秒數（觸發預警）</label>
          <input 
            type="number" 
            v-model.number="holdSeconds" 
            min="1" 
            step="1"
            class="w-full px-3 py-2 bg-gray-800 border border-purple-500/30 rounded-lg text-white focus:outline-none focus:border-purple-500"
          />
        </div>

        <p class="text-purple-300/70 text-xs">
          依 crowd safety 文獻：&gt;5 人/㎡ 高風險、6–7 人/㎡ 極危險；10–30 秒是關鍵反應窗。
        </p>

        <!-- 密度分級標準 -->
        <div class="p-4 bg-gray-800/50 rounded-lg space-y-2">
          <h3 class="text-white font-bold mb-2">📊 密度分級標準</h3>
          <div class="flex items-center gap-2">
            <span class="w-3 h-3 bg-green-500 rounded-full"></span>
            <span class="text-green-200 text-sm">&lt; {{ densityWarn }} 人/㎡ - 正常 (低風險)</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="w-3 h-3 bg-orange-500 rounded-full"></span>
            <span class="text-orange-200 text-sm">{{ densityWarn }} - {{ densityDanger }} 人/㎡ - 警告 (高風險)</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="w-3 h-3 bg-red-500 rounded-full"></span>
            <span class="text-red-200 text-sm">≥ {{ densityDanger }} 人/㎡ - 危險 (極危險)</span>
          </div>
        </div>
      </div>
    </aside>

    <!-- Main Content Area -->
    <div class="flex-1 flex flex-col min-h-screen overflow-x-hidden">
      <!-- Header -->
      <header class="text-center py-6 px-4 bg-black/20">
        <h1 class="text-3xl md:text-4xl font-bold text-white mb-2 drop-shadow-2xl">
          🎯 群眾密度監控系統
        </h1>
        <p class="text-lg text-purple-200">AI 驅動的即時人流偵測與警報</p>
      </header>

      <!-- Main Content -->
      <main class="flex-1 flex flex-col items-center px-4 pb-8 space-y-6 py-4">
        <!-- Input Source Selection -->
        <div class="w-full max-w-4xl bg-gray-800/50 backdrop-blur-xl rounded-xl p-4 shadow-xl border border-purple-500/20">
          <h3 class="text-white font-bold mb-3">選擇輸入來源</h3>
          <div class="flex flex-wrap gap-2">
            <button 
              @click="inputSource = 'image'"
              :class="[
                'px-4 py-2 rounded-lg font-medium transition-all',
                inputSource === 'image' 
                  ? 'bg-purple-600 text-white' 
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              ]"
            >
              📷 上傳圖片
            </button>
            <button 
              @click="inputSource = 'video'"
              :class="[
                'px-4 py-2 rounded-lg font-medium transition-all',
                inputSource === 'video' 
                  ? 'bg-purple-600 text-white' 
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              ]"
            >
              🎬 上傳影片
            </button>
            <button 
              @click="inputSource = 'url'"
              :class="[
                'px-4 py-2 rounded-lg font-medium transition-all',
                inputSource === 'url' 
                  ? 'bg-purple-600 text-white' 
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              ]"
            >
              🔗 影片連結
            </button>
            <button 
              @click="inputSource = 'camera'"
              :class="[
                'px-4 py-2 rounded-lg font-medium transition-all',
                inputSource === 'camera' 
                  ? 'bg-purple-600 text-white' 
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              ]"
            >
              📹 拍照
            </button>
          </div>
        </div>

        <!-- Video Container -->
        <div class="w-full max-w-4xl h-[400px] md:h-[500px] bg-gray-900 rounded-xl overflow-hidden shadow-2xl border border-purple-500/30 flex items-center justify-center relative">
          <video ref="videoRef" class="hidden" autoplay playsinline></video>
          <video ref="uploadVideoRef" v-if="uploadedVideoUrl" :src="uploadedVideoUrl" class="hidden" playsinline></video>
          <canvas ref="canvasRef" class="max-w-full max-h-full object-contain bg-black"></canvas>
          
          <!-- Alert Overlay -->
          <div 
            v-if="showAlert" 
            class="absolute inset-0 flex items-center justify-center bg-red-600/20 animate-pulse pointer-events-none"
          >
            <div class="bg-red-600/90 text-white px-8 py-4 rounded-xl text-2xl font-bold shadow-2xl">
              ⚠️ ALERT: CROWD RISK!
            </div>
          </div>
        </div>

        <!-- Input Source Controls -->
        <div class="w-full max-w-4xl bg-gray-800/50 backdrop-blur-xl rounded-xl p-4 shadow-xl border border-purple-500/20">
          <!-- Image Upload -->
          <div v-if="inputSource === 'image'" class="flex flex-wrap justify-center gap-3">
            <button 
              @click="triggerFileInput" 
              :disabled="isUploading"
              class="px-6 py-3 bg-gradient-to-r from-purple-600 to-indigo-700 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-purple-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 border border-purple-400/30"
            >
              📷 {{ isUploading ? '上傳中...' : '選擇圖片' }}
            </button>
            <button 
              v-if="uploadedImageUrl" 
              @click="clearUpload" 
              class="px-6 py-3 bg-gradient-to-r from-orange-600 to-orange-700 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-orange-500/50 transition-all border border-orange-400/30"
            >
              🗑️ 清除
            </button>
            <input 
              ref="fileInputRef" 
              type="file" 
              accept="image/*" 
              @change="handleFileUpload" 
              class="hidden"
            />
          </div>

          <!-- Video Upload -->
          <div v-else-if="inputSource === 'video'" class="flex flex-wrap justify-center gap-3">
            <button 
              @click="triggerVideoInput" 
              :disabled="isPlayingVideo"
              class="px-6 py-3 bg-gradient-to-r from-blue-600 to-blue-700 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-blue-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 border border-blue-400/30"
            >
              🎬 選擇影片
            </button>
            <button 
              v-if="isPlayingVideo" 
              @click="stopVideoPlayback" 
              class="px-6 py-3 bg-gradient-to-r from-red-600 to-red-800 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-red-500/50 transition-all border border-red-400/30"
            >
              ⏹️ 停止播放
            </button>
            <button 
              v-if="uploadedVideoUrl && !isPlayingVideo" 
              @click="clearUpload" 
              class="px-6 py-3 bg-gradient-to-r from-orange-600 to-orange-700 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-orange-500/50 transition-all border border-orange-400/30"
            >
              🗑️ 清除
            </button>
            <input 
              ref="videoFileInputRef" 
              type="file" 
              accept="video/*" 
              @change="handleVideoUpload" 
              class="hidden"
            />
          </div>

          <!-- Video URL -->
          <div v-else-if="inputSource === 'url'" class="space-y-3">
            <div class="flex gap-2">
              <input 
                type="text" 
                v-model="videoUrl" 
                placeholder="請貼上影片連結（mp4/avi/mov 直連網址）"
                class="flex-1 px-4 py-3 bg-gray-700 border border-purple-500/30 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:border-purple-500"
              />
              <button 
                @click="loadVideoUrl" 
                :disabled="isPlayingVideo || !videoUrl"
                class="px-6 py-3 bg-gradient-to-r from-purple-600 to-indigo-700 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-purple-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 border border-purple-400/30"
              >
                ▶️ 載入
              </button>
            </div>
            <div class="flex justify-center gap-3">
              <button 
                v-if="isPlayingVideo" 
                @click="stopVideoPlayback" 
                class="px-6 py-3 bg-gradient-to-r from-red-600 to-red-800 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-red-500/50 transition-all border border-red-400/30"
              >
                ⏹️ 停止播放
              </button>
            </div>
          </div>

          <!-- Camera -->
          <div v-else-if="inputSource === 'camera'" class="flex flex-wrap justify-center gap-3">
            <button 
              v-if="!isStreaming" 
              @click="startStream" 
              class="px-6 py-3 bg-gradient-to-r from-green-600 to-emerald-700 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-green-500/50 transition-all border border-green-400/30"
            >
              📹 開始監控
            </button>
            <button 
              v-else 
              @click="stopStream" 
              class="px-6 py-3 bg-gradient-to-r from-red-600 to-red-800 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-red-500/50 transition-all border border-red-400/30"
            >
              ⏸️ 停止監控
            </button>
          </div>
        </div>

        <!-- Info Panel -->
        <div class="w-full max-w-4xl bg-gray-800/50 backdrop-blur-xl rounded-xl p-6 shadow-2xl border border-purple-500/20">
          <!-- Stats Grid -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <!-- Person Count -->
            <div class="bg-gradient-to-br from-blue-600/30 to-blue-800/30 border border-blue-500/30 rounded-lg p-4 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-lg">
              <div class="text-blue-200 text-sm mb-2 font-medium">人數</div>
              <div class="text-white text-3xl font-bold drop-shadow-lg">{{ personCount }}</div>
            </div>
            
            <!-- Density -->
            <div class="bg-gradient-to-br from-purple-600/30 to-purple-800/30 border border-purple-500/30 rounded-lg p-4 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-lg">
              <div class="text-purple-200 text-sm mb-2 font-medium">密度</div>
              <div class="text-white text-3xl font-bold drop-shadow-lg">
                {{ density.toFixed(2) }}
                <span class="text-sm">人/㎡</span>
              </div>
            </div>
            
            <!-- Status -->
            <div 
              class="rounded-lg p-4 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-lg"
              :class="{
                'bg-gradient-to-br from-green-600/30 to-green-800/30 border border-green-500/50': status === 'normal',
                'bg-gradient-to-br from-yellow-600/30 to-yellow-800/30 border border-yellow-500/50 animate-pulse': status === 'warning',
                'bg-gradient-to-br from-red-600/30 to-red-800/30 border border-red-500/50 animate-pulse': status === 'danger'
              }"
            >
              <div 
                class="text-sm mb-2 font-medium"
                :class="{
                  'text-green-200': status === 'normal',
                  'text-yellow-200': status === 'warning',
                  'text-red-200': status === 'danger'
                }"
              >
                狀態
              </div>
              <div class="text-white text-3xl font-bold drop-shadow-lg">{{ getStatusText() }}</div>
            </div>

            <!-- Over Threshold Time -->
            <div 
              class="rounded-lg p-4 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-lg"
              :class="secondsOverThreshold > 0 
                ? 'bg-gradient-to-br from-orange-600/30 to-orange-800/30 border border-orange-500/50' 
                : 'bg-gradient-to-br from-gray-600/30 to-gray-800/30 border border-gray-500/30'"
            >
              <div class="text-orange-200 text-sm mb-2 font-medium">超標時間</div>
              <div class="text-white text-3xl font-bold drop-shadow-lg">
                {{ secondsOverThreshold.toFixed(1) }}
                <span class="text-sm">秒</span>
              </div>
            </div>
          </div>

          <!-- Density Bar -->
          <div class="mb-6">
            <div class="text-purple-200 text-sm mb-2 font-medium">密度條</div>
            <div class="w-full h-6 bg-gray-700 rounded-lg overflow-hidden border border-gray-600">
              <div 
                class="h-full transition-all duration-300"
                :class="densityBarColor"
                :style="{ width: `${densityRatio * 100}%` }"
              ></div>
            </div>
            <div class="flex justify-between text-xs text-gray-400 mt-1">
              <span>0</span>
              <span class="text-yellow-400">{{ densityWarn }}</span>
              <span class="text-red-400">{{ densityDanger }}</span>
            </div>
          </div>

          <!-- Last Update -->
          <div v-if="lastUpdate" class="text-center text-purple-300 text-sm font-medium">
            最後更新: {{ lastUpdate.toLocaleTimeString('zh-TW') }}
          </div>
        </div>
      </main>

      <!-- Footer -->
      <footer class="bg-black/40 text-center py-4 text-purple-200 text-sm border-t border-purple-500/20">
        <p>API: {{ apiUrl }} | ROI: {{ useRoi ? '啟用' : '停用' }} | 面積: {{ areaM2 }}㎡</p>
      </footer>
    </div>
  </div>
</template>


