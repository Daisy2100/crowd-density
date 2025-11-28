<script setup lang="ts">
import { ref, computed, onBeforeUnmount, nextTick } from 'vue'

// ============== 常數定義 ==============
const MIN_DENSITY_THRESHOLD = 0.001
const VIDEO_DETECTION_INTERVAL_MS = 1000

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
// 響應式側邊欄狀態：桌面版預設打開，手機版預設收起
const sidebarOpen = ref(window.innerWidth >= 1024)

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
// API URL: 自動根據當前網站 domain 決定
const getApiUrl = () => {
  const hostname = window.location.hostname
  // 如果是 localhost 或 127.0.0.1，使用本地 API
  if (hostname === 'localhost' || hostname === '127.0.0.1') {
    return 'http://localhost:8001'
  }
  // 否則使用當前網站的 protocol 和 hostname
  return `${window.location.protocol}//${hostname}`
}
const apiUrl = ref(getApiUrl())
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

  // 使用全域常數 VIDEO_DETECTION_INTERVAL_MS (ms)
  streamInterval = window.setInterval(() => {
    captureAndDetect()
  }, VIDEO_DETECTION_INTERVAL_MS)
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

// ============== 輸入來源按鈕處理 ==============
const selectImageSource = () => {
  inputSource.value = 'image'
  triggerFileInput()
}

const selectVideoSource = () => {
  inputSource.value = 'video'
  triggerVideoInput()
}

const selectUrlSource = () => {
  inputSource.value = 'url'
}

const selectCameraSource = () => {
  inputSource.value = 'camera'
  if (!isStreaming.value) {
    startStream()
  }
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

// ============== 監聽視窗大小變化 ==============
const handleResize = () => {
  // 當視窗從手機尺寸變為桌面尺寸時，自動打開側邊欄
  if (window.innerWidth >= 1024 && !sidebarOpen.value) {
    sidebarOpen.value = true
  }
}

// 添加視窗大小監聽器
window.addEventListener('resize', handleResize)

onBeforeUnmount(() => {
  stopStream()
  stopVideoPlayback()
  window.removeEventListener('resize', handleResize)
})
</script>

<template>
  <div class="h-screen flex bg-gradient-to-br from-blue-50 via-white to-cyan-50 overflow-hidden">
    <!-- Sidebar Toggle Button -->
    <button 
      @click="toggleSidebar"
      class="fixed top-6 z-50 group transition-all duration-300"
      :class="sidebarOpen ? 'left-[19rem]' : 'left-4'"
    >
      <!-- 按鈕背景 -->
      <div class="relative w-12 h-12 bg-white rounded-full shadow-lg border-2 border-blue-200 group-hover:border-blue-400 transition-all duration-300 group-hover:shadow-xl flex items-center justify-center">
        <!-- 圖示 -->
        <svg 
          class="w-6 h-6 text-blue-600 transition-transform duration-300"
          :class="sidebarOpen ? 'rotate-180' : ''"
          fill="none" 
          stroke="currentColor" 
          viewBox="0 0 24 24"
        >
          <path 
            v-if="!sidebarOpen"
            stroke-linecap="round" 
            stroke-linejoin="round" 
            stroke-width="2.5" 
            d="M4 6h16M4 12h16M4 18h16"
          />
          <path 
            v-else
            stroke-linecap="round" 
            stroke-linejoin="round" 
            stroke-width="2.5" 
            d="M15 19l-7-7 7-7"
          />
        </svg>
        
        <!-- 脈動效果 -->
        <span class="absolute inset-0 rounded-full bg-blue-400 opacity-0 group-hover:opacity-20 group-hover:animate-ping"></span>
      </div>
      
      <!-- Tooltip -->
      <div class="absolute left-14 top-1/2 -translate-y-1/2 bg-gray-800 text-white text-xs px-3 py-1.5 rounded-lg opacity-0 group-hover:opacity-100 transition-opacity duration-200 pointer-events-none whitespace-nowrap shadow-lg">
        {{ sidebarOpen ? '收起控制面板' : '展開控制面板' }}
        <div class="absolute left-0 top-1/2 -translate-y-1/2 -translate-x-1 w-2 h-2 bg-gray-800 rotate-45"></div>
      </div>
    </button>

    <!-- Sidebar -->
    <aside 
      :class="[
        'fixed lg:relative z-40 w-80 h-screen bg-white border-r border-gray-200 overflow-y-auto transition-all duration-300 flex-shrink-0 shadow-xl',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full'
      ]"
    >
      <div class="p-6 space-y-6">
        <div class="bg-gradient-to-r from-blue-500 to-cyan-500 rounded-2xl p-5 shadow-lg">
          <h2 class="text-xl font-bold text-white flex items-center gap-2">
            <span class="text-2xl">⚙️</span> 設定面板
          </h2>
          <p class="text-blue-50 text-xs mt-1">調整監控參數與閾值</p>
        </div>

        <!-- ROI 設定 -->
        <div class="space-y-4 bg-gray-50 rounded-2xl p-5 border border-gray-200 shadow-md">
          <div class="flex items-center gap-3 pb-3 border-b border-gray-200">
            <input 
              type="checkbox" 
              v-model="useRoi" 
              id="useRoi"
              class="w-5 h-5 accent-blue-500 cursor-pointer"
            />
            <label for="useRoi" class="text-gray-800 font-semibold cursor-pointer flex items-center gap-2">
              <span class="text-lg">🎯</span> 啟用 ROI 區域裁切
            </label>
          </div>
          
          <div v-if="useRoi" class="grid grid-cols-2 gap-4 p-4 bg-white rounded-xl border border-blue-200 shadow-sm">
            <div>
              <label class="block text-gray-700 text-sm mb-2 font-medium">← 左邊界</label>
              <input 
                type="range" 
                v-model.number="roiX0" 
                min="0" 
                max="90" 
                class="w-full accent-blue-500 h-2 cursor-pointer"
              />
              <div class="text-gray-800 text-center font-bold mt-1 bg-blue-100 rounded-lg py-1">{{ roiX0 }}%</div>
            </div>
            <div>
              <label class="block text-gray-700 text-sm mb-2 font-medium">↑ 上邊界</label>
              <input 
                type="range" 
                v-model.number="roiY0" 
                min="0" 
                max="90" 
                class="w-full accent-blue-500 h-2 cursor-pointer"
              />
              <div class="text-gray-800 text-center font-bold mt-1 bg-blue-100 rounded-lg py-1">{{ roiY0 }}%</div>
            </div>
            <div>
              <label class="block text-gray-700 text-sm mb-2 font-medium">→ 右邊界</label>
              <input 
                type="range" 
                v-model.number="roiX1" 
                min="10" 
                max="100" 
                class="w-full accent-blue-500 h-2 cursor-pointer"
              />
              <div class="text-gray-800 text-center font-bold mt-1 bg-blue-100 rounded-lg py-1">{{ roiX1 }}%</div>
            </div>
            <div>
              <label class="block text-gray-700 text-sm mb-2 font-medium">↓ 下邊界</label>
              <input 
                type="range" 
                v-model.number="roiY1" 
                min="10" 
                max="100" 
                class="w-full accent-blue-500 h-2 cursor-pointer"
              />
              <div class="text-gray-800 text-center font-bold mt-1 bg-blue-100 rounded-lg py-1">{{ roiY1 }}%</div>
            </div>
          </div>
        </div>

        <!-- 區域面積 -->
        <div class="bg-gray-50 rounded-2xl p-5 border border-gray-200 shadow-md">
          <label class="flex items-center gap-2 text-gray-700 text-sm mb-2 font-semibold">
            <span class="text-lg">📐</span> 監控區域實際面積 (㎡)
          </label>
          <input 
            type="number" 
            v-model.number="areaM2" 
            min="1" 
            step="1"
            class="w-full px-4 py-3 bg-white border-2 border-blue-300 rounded-xl text-gray-800 font-semibold text-lg focus:outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-200 transition-all"
          />
        </div>

        <!-- 警告門檻 -->
        <div class="bg-orange-50 rounded-2xl p-5 border border-orange-200 shadow-md">
          <label class="flex items-center gap-2 text-orange-700 text-sm mb-2 font-semibold">
            <span class="text-lg">⚠️</span> 警告門檻 (人/㎡)
          </label>
          <input 
            type="number" 
            v-model.number="densityWarn" 
            min="0.5" 
            step="0.5"
            class="w-full px-4 py-3 bg-white border-2 border-orange-300 rounded-xl text-gray-800 font-semibold text-lg focus:outline-none focus:border-orange-500 focus:ring-2 focus:ring-orange-200 transition-all"
          />
        </div>

        <!-- 危險門檻 -->
        <div class="bg-red-50 rounded-2xl p-5 border border-red-200 shadow-md">
          <label class="flex items-center gap-2 text-red-700 text-sm mb-2 font-semibold">
            <span class="text-lg">🚨</span> 危險門檻 (人/㎡)
          </label>
          <input 
            type="number" 
            v-model.number="densityDanger" 
            min="1" 
            step="0.5"
            class="w-full px-4 py-3 bg-white border-2 border-red-300 rounded-xl text-gray-800 font-semibold text-lg focus:outline-none focus:border-red-500 focus:ring-2 focus:ring-red-200 transition-all"
          />
        </div>

        <!-- 連續超標秒數 -->
        <div class="bg-gray-800/70 rounded-xl p-4 border border-gray-700/50 shadow-lg">
          <label class="flex items-center gap-2 text-purple-100 text-sm mb-2 font-semibold">
            <span class="text-lg">⏱️</span> 連續超標秒數（觸發預警）
          </label>
          <input 
            type="number" 
            v-model.number="holdSeconds" 
            min="1" 
            step="1"
            class="w-full px-4 py-3 bg-gray-900 border-2 border-purple-500/40 rounded-lg text-white font-semibold text-lg focus:outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/50 transition-all"
          />
        </div>

        <div class="p-4 bg-gradient-to-r from-purple-900/40 to-indigo-900/40 rounded-xl border border-purple-500/30">
          <p class="text-purple-100 text-xs leading-relaxed font-medium">
            💡 依 crowd safety 文獻：&gt;5 人/㎡ 高風險、6–7 人/㎡ 極危險；10–30 秒是關鍵反應窗。
          </p>
        </div>

        <!-- 密度分級標準 -->
        <div class="p-5 bg-white rounded-2xl space-y-3 border border-gray-200 shadow-lg">
          <h3 class="text-gray-800 font-bold mb-3 flex items-center gap-2 text-lg">
            <span>📊</span> 密度分級標準
          </h3>
          <div class="flex items-center gap-3 p-3 bg-green-50 rounded-xl hover:bg-green-100 transition-all border border-green-200">
            <span class="w-4 h-4 bg-green-500 rounded-full shadow-md"></span>
            <span class="text-green-700 text-sm font-semibold">&lt; {{ densityWarn }} 人/㎡ - 正常 (低風險)</span>
          </div>
          <div class="flex items-center gap-3 p-3 bg-orange-50 rounded-xl hover:bg-orange-100 transition-all border border-orange-200">
            <span class="w-4 h-4 bg-orange-500 rounded-full shadow-md"></span>
            <span class="text-orange-700 text-sm font-semibold">{{ densityWarn }} - {{ densityDanger }} 人/㎡ - 警告 (高風險)</span>
          </div>
          <div class="flex items-center gap-3 p-3 bg-red-50 rounded-xl hover:bg-red-100 transition-all border border-red-200">
            <span class="w-4 h-4 bg-red-500 rounded-full shadow-md animate-pulse"></span>
            <span class="text-red-700 text-sm font-semibold">≥ {{ densityDanger }} 人/㎡ - 危險 (極危險)</span>
          </div>
        </div>
      </div>
    </aside>

    <!-- Main Content Area -->
    <div class="flex-1 flex flex-col h-screen overflow-hidden">
      <!-- Header -->
      <header class="text-center py-6 px-4 bg-white/80 backdrop-blur-sm flex-shrink-0 border-b border-gray-200 shadow-sm">
        <h1 class="text-3xl md:text-4xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-blue-600 via-cyan-600 to-blue-600 mb-2 animate-gradient">
          🎯 群眾密度監控系統
        </h1>
        <p class="text-sm md:text-base text-gray-600 font-medium">🤖 AI 驅動的即時人流偵測與智能警報系統</p>
      </header>

      <!-- Main Content -->
      <main class="flex-1 flex flex-col items-center px-4 pb-4 space-y-4 py-2 overflow-y-auto">
        <!-- Input Source Selection -->
        <div class="w-full max-w-4xl bg-white rounded-2xl p-6 shadow-lg border border-gray-200">
          <h3 class="text-gray-800 font-bold mb-4 text-lg flex items-center gap-2">
            <span class="text-xl">🎬</span> 選擇輸入來源
          </h3>
          <div class="flex flex-wrap gap-3">
            <button 
              @click="selectImageSource"
              :class="[
                'px-6 py-3 rounded-xl font-semibold transition-all transform hover:scale-105 shadow-md',
                inputSource === 'image' 
                  ? 'bg-gradient-to-r from-blue-500 to-cyan-500 text-white shadow-blue-300 ring-2 ring-blue-300' 
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-300'
              ]"
            >
              📷 上傳圖片
            </button>
            <button 
              @click="selectVideoSource"
              :class="[
                'px-6 py-3 rounded-xl font-semibold transition-all transform hover:scale-105 shadow-md',
                inputSource === 'video' 
                  ? 'bg-gradient-to-r from-blue-500 to-cyan-500 text-white shadow-blue-300 ring-2 ring-blue-300' 
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-300'
              ]"
            >
              🎬 上傳影片
            </button>
            <button 
              @click="selectUrlSource"
              :class="[
                'px-6 py-3 rounded-xl font-semibold transition-all transform hover:scale-105 shadow-md',
                inputSource === 'url' 
                  ? 'bg-gradient-to-r from-blue-500 to-cyan-500 text-white shadow-blue-300 ring-2 ring-blue-300' 
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-300'
              ]"
            >
              🔗 影片連結
            </button>
            <button 
              @click="selectCameraSource"
              :class="[
                'px-6 py-3 rounded-xl font-semibold transition-all transform hover:scale-105 shadow-md',
                inputSource === 'camera' 
                  ? 'bg-gradient-to-r from-blue-500 to-cyan-500 text-white shadow-blue-300 ring-2 ring-blue-300' 
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-300'
              ]"
            >
              📹 即時監控
            </button>
          </div>
        </div>

        <!-- Video Container -->
        <div class="w-full max-w-4xl h-[280px] md:h-[350px] bg-gray-100 rounded-2xl overflow-hidden shadow-lg border-2 border-gray-300 flex items-center justify-center relative flex-shrink-0">
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
        <div class="w-full max-w-4xl bg-white rounded-2xl p-5 shadow-lg border border-gray-200">
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
                class="flex-1 px-4 py-3 bg-white border-2 border-gray-300 rounded-xl text-gray-800 placeholder-gray-400 focus:outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-200 transition-all"
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
                class="px-6 py-3 bg-gradient-to-r from-red-400 to-red-500 text-white font-bold rounded-xl hover:scale-105 hover:shadow-lg transition-all"
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
              class="px-6 py-3 bg-gradient-to-r from-green-400 to-emerald-500 text-white font-bold rounded-xl hover:scale-105 hover:shadow-lg transition-all"
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
        <div class="w-full max-w-4xl bg-white rounded-2xl p-6 shadow-lg border border-gray-200">
          <!-- Stats Grid -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <!-- Person Count -->
            <div class="bg-gradient-to-br from-blue-50 to-blue-100 border-2 border-blue-300 rounded-2xl p-5 text-center hover:transform hover:-translate-y-1 hover:shadow-xl transition-all duration-300 shadow-md">
              <div class="text-blue-600 text-xs uppercase tracking-wider mb-2 font-bold">👥 人數</div>
              <div class="text-blue-700 text-4xl font-extrabold">{{ personCount }}</div>
            </div>
            
            <!-- Density -->
            <div class="bg-gradient-to-br from-cyan-50 to-cyan-100 border-2 border-cyan-300 rounded-2xl p-5 text-center hover:transform hover:-translate-y-1 hover:shadow-xl transition-all duration-300 shadow-md">
              <div class="text-cyan-600 text-xs uppercase tracking-wider mb-2 font-bold">📊 密度</div>
              <div class="text-cyan-700 text-4xl font-extrabold">
                {{ density.toFixed(2) }}
                <span class="text-base">人/㎡</span>
              </div>
            </div>
            
            <!-- Status -->
            <div 
              class="rounded-2xl p-5 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-md"
              :class="{
                'bg-gradient-to-br from-green-50 to-green-100 border-2 border-green-300 hover:shadow-xl': status === 'normal',
                'bg-gradient-to-br from-orange-50 to-orange-100 border-2 border-orange-300 animate-pulse hover:shadow-xl': status === 'warning',
                'bg-gradient-to-br from-red-50 to-red-100 border-2 border-red-300 animate-pulse hover:shadow-xl': status === 'danger'
              }"
            >
              <div 
                class="text-xs uppercase tracking-wider mb-2 font-bold"
                :class="{
                  'text-green-600': status === 'normal',
                  'text-orange-600': status === 'warning',
                  'text-red-600': status === 'danger'
                }"
              >
                {{ status === 'normal' ? '✅' : status === 'warning' ? '⚠️' : '🚨' }} 狀態
              </div>
              <div 
                class="text-4xl font-extrabold"
                :class="{
                  'text-green-700': status === 'normal',
                  'text-orange-700': status === 'warning',
                  'text-red-700': status === 'danger'
                }"
              >{{ getStatusText() }}</div>
            </div>

            <!-- Over Threshold Time -->
            <div 
              class="rounded-2xl p-5 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-md"
              :class="secondsOverThreshold > 0 
                ? 'bg-gradient-to-br from-orange-50 to-orange-100 border-2 border-orange-300 hover:shadow-xl' 
                : 'bg-gradient-to-br from-gray-50 to-gray-100 border-2 border-gray-300'"
            >
              <div 
                class="text-xs uppercase tracking-wider mb-2 font-bold"
                :class="secondsOverThreshold > 0 ? 'text-orange-600' : 'text-gray-500'"
              >
                ⏱️ 超標時間
              </div>
              <div 
                class="text-4xl font-extrabold"
                :class="secondsOverThreshold > 0 ? 'text-orange-700' : 'text-gray-600'"
              >
                {{ secondsOverThreshold.toFixed(1) }}
                <span class="text-base">秒</span>
              </div>
            </div>
          </div>

          <!-- Density Bar -->
          <div class="mb-6">
            <div class="text-gray-700 text-sm mb-3 font-bold flex items-center gap-2">
              <span>📈</span> 密度視覺化
            </div>
            <div class="w-full h-8 bg-gray-100 rounded-xl overflow-hidden border-2 border-gray-300 shadow-sm relative">
              <div 
                class="h-full transition-all duration-500 ease-out"
                :class="densityBarColor"
                :style="{ width: `${densityRatio * 100}%` }"
              ></div>
              <!-- 閾值標記 -->
              <div 
                class="absolute top-0 bottom-0 w-0.5 bg-orange-400"
                :style="{ left: `${(densityWarn / Math.max(densityDanger, 0.001)) * 100}%` }"
              ></div>
            </div>
            <div class="flex justify-between text-sm font-semibold mt-2">
              <span class="text-green-600">0</span>
              <span class="text-orange-600">⚠️ {{ densityWarn }}</span>
              <span class="text-red-600">🚨 {{ densityDanger }}</span>
            </div>
          </div>

          <!-- Last Update -->
          <div v-if="lastUpdate" class="text-center text-gray-700 text-sm font-semibold bg-blue-50 py-3 px-4 rounded-xl border border-blue-200 shadow-sm">
            <span class="text-blue-500">🕐</span> 最後更新: {{ lastUpdate.toLocaleTimeString('zh-TW') }}
          </div>
        </div>
      </main>

      <!-- Footer -->
      <footer class="bg-white/90 backdrop-blur-sm text-center py-3 text-gray-600 text-xs border-t border-gray-200 flex-shrink-0 shadow-sm">
        <div class="flex justify-center items-center gap-4 flex-wrap">
          <span class="bg-blue-50 px-3 py-1 rounded-full border border-blue-200">🔗 API: {{ apiUrl }}</span>
          <span class="bg-cyan-50 px-3 py-1 rounded-full border border-cyan-200">🎯 ROI: {{ useRoi ? '✅ 啟用' : '❌ 停用' }}</span>
          <span class="bg-blue-50 px-3 py-1 rounded-full border border-blue-200">📐 面積: {{ areaM2 }}㎡</span>
        </div>
      </footer>
    </div>
  </div>
</template>


