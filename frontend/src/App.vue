<script setup lang="ts">
import { ref, onBeforeUnmount } from 'vue'

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

const videoRef = ref<HTMLVideoElement | null>(null)
const canvasRef = ref<HTMLCanvasElement | null>(null)
const personCount = ref(0)
const density = ref(0)
const status = ref('normal')
const isStreaming = ref(false)
const lastUpdate = ref<Date | null>(null)
const apiUrl = ref(import.meta.env.VITE_API_URL || 'http://localhost:8001')
const fileInputRef = ref<HTMLInputElement | null>(null)
const uploadedImageUrl = ref<string | null>(null)
const isUploading = ref(false)

let streamInterval: number | null = null

// 開始視訊串流
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
      startDetection()
    }
  } catch (error) {
    console.error('無法存取攝影機:', error)
    alert('無法存取攝影機,請確認權限設定')
  }
}

// 停止視訊串流
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
  personCount.value = 0
  density.value = 0
  status.value = 'normal'
}

// 開始偵測 (每 2000ms)
const startDetection = () => {
  if (streamInterval) {
    clearInterval(streamInterval)
  }
  
  streamInterval = window.setInterval(() => {
    captureAndDetect()
  }, 2000)
}

// 擷取並偵測
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
      const formData = new FormData()
      formData.append('file', blob, 'frame.jpg')
      formData.append('roi_area_m2', '20')
      formData.append('density_warn', '5.0')
      formData.append('density_danger', '6.5')
      
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
      }
    } catch (error) {
      console.error('偵測失敗:', error)
    }
  }, 'image/jpeg', 0.8)
}

// 繪製偵測結果
const drawResults = (ctx: CanvasRenderingContext2D, result: DetectionResult) => {
  result.bounding_boxes.forEach(box => {
    ctx.strokeStyle = '#3CFF64'
    ctx.lineWidth = 2
    ctx.strokeRect(box.x1, box.y1, box.x2 - box.x1, box.y2 - box.y1)
  })
  
  const color = status.value === 'danger' ? '#FF3C3C' : 
                status.value === 'warning' ? '#FFA500' : '#3CFF64'
  
  ctx.fillStyle = 'rgba(0, 0, 0, 0.6)'
  ctx.fillRect(10, 10, 320, 90)
  
  ctx.fillStyle = color
  ctx.font = 'bold 24px Arial'
  ctx.fillText(`密度: ${density.value.toFixed(2)} 人/㎡`, 20, 45)
  
  ctx.fillStyle = '#FFFFFF'
  ctx.font = '18px Arial'
  ctx.fillText(`人數: ${personCount.value}`, 20, 75)
}

// 處理圖片上傳
const handleFileUpload = (event: Event) => {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  
  if (file && file.type.startsWith('image/')) {
    uploadAndDetect(file)
  }
}

// 上傳並偵測圖片
const uploadAndDetect = async (file: File) => {
  if (!canvasRef.value) return
  
  isUploading.value = true
  
  try {
    if (isStreaming.value) {
      stopStream()
    }
    
    const reader = new FileReader()
    reader.onload = async (e) => {
      const img = new Image()
      img.onload = async () => {
        const canvas = canvasRef.value!
        const ctx = canvas.getContext('2d')!
        
        canvas.width = img.width
        canvas.height = img.height
        
        ctx.drawImage(img, 0, 0)
        
        const formData = new FormData()
        formData.append('file', file)
        formData.append('roi_area_m2', '20')
        formData.append('density_warn', '5.0')
        formData.append('density_danger', '6.5')
        
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

// 觸發檔案選擇
const triggerFileInput = () => {
  fileInputRef.value?.click()
}

// 清除上傳的圖片
const clearUpload = () => {
  uploadedImageUrl.value = null
  personCount.value = 0
  density.value = 0
  status.value = 'normal'
  
  if (canvasRef.value) {
    const ctx = canvasRef.value.getContext('2d')
    ctx?.clearRect(0, 0, canvasRef.value.width, canvasRef.value.height)
  }
}

// 取得狀態文字
const getStatusText = () => {
  switch (status.value) {
    case 'danger': return '危險'
    case 'warning': return '警告'
    default: return '正常'
  }
}

onBeforeUnmount(() => {
  stopStream()
})
</script>

<template>
  <div class="min-h-screen flex flex-col bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
    <!-- Header -->
    <header class="text-center py-8 px-4 bg-black/20">
      <h1 class="text-4xl md:text-5xl font-bold text-white mb-2 drop-shadow-2xl">
        🎯 群眾密度監控系統
      </h1>
      <p class="text-lg md:text-xl text-purple-200">AI 驅動的即時人流偵測與警報</p>
    </header>

    <!-- Main Content -->
    <main class="flex-1 flex flex-col items-center px-4 pb-8 space-y-6 py-6">
      <!-- Video Container -->
      <div class="w-full max-w-5xl h-[500px] md:h-[600px] bg-gray-900 rounded-xl overflow-hidden shadow-2xl border border-purple-500/30 flex items-center justify-center">
        <video ref="videoRef" class="hidden" autoplay playsinline></video>
        <canvas ref="canvasRef" class="max-w-full max-h-full object-contain bg-black"></canvas>
      </div>

      <!-- Info Panel -->
      <div class="w-full max-w-3xl bg-gray-800/50 backdrop-blur-xl rounded-xl p-6 shadow-2xl border border-purple-500/20">
        <!-- Stats Grid -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <!-- Person Count -->
          <div class="bg-gradient-to-br from-blue-600/30 to-blue-800/30 border border-blue-500/30 rounded-lg p-6 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-lg">
            <div class="text-blue-200 text-sm mb-2 font-medium">人數</div>
            <div class="text-white text-4xl font-bold drop-shadow-lg">{{ personCount }}</div>
          </div>
          
          <!-- Density -->
          <div class="bg-gradient-to-br from-purple-600/30 to-purple-800/30 border border-purple-500/30 rounded-lg p-6 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-lg">
            <div class="text-purple-200 text-sm mb-2 font-medium">密度</div>
            <div class="text-white text-4xl font-bold drop-shadow-lg">
              {{ density.toFixed(2) }}
              <span class="text-lg">人/㎡</span>
            </div>
          </div>
          
          <!-- Status -->
          <div 
            class="rounded-lg p-6 text-center hover:transform hover:-translate-y-1 transition-all duration-300 shadow-lg"
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
            <div class="text-white text-4xl font-bold drop-shadow-lg">{{ getStatusText() }}</div>
          </div>
        </div>

        <!-- Controls -->
        <div class="flex flex-wrap justify-center gap-3 mb-4">
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
          
          <button 
            @click="triggerFileInput" 
            :disabled="isUploading || isStreaming"
            class="px-6 py-3 bg-gradient-to-r from-purple-600 to-indigo-700 text-white font-bold rounded-lg hover:scale-105 hover:shadow-2xl hover:shadow-purple-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 border border-purple-400/30"
          >
            📸 {{ isUploading ? '上傳中...' : '上傳圖片' }}
          </button>
          
          <button 
            v-if="uploadedImageUrl && !isStreaming" 
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

        <!-- Last Update -->
        <div v-if="lastUpdate" class="text-center text-purple-300 text-sm font-medium">
          最後更新: {{ lastUpdate.toLocaleTimeString('zh-TW') }}
        </div>
      </div>
    </main>

    <!-- Footer -->
    <footer class="bg-black/40 text-center py-4 text-purple-200 text-sm border-t border-purple-500/20">
      <p>API: {{ apiUrl }} | 更新頻率: 2000ms (0.5 FPS)</p>
    </footer>
  </div>
</template>


