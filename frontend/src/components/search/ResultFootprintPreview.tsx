interface ResultFootprintPreviewProps {
  bbox?: [number, number, number, number]
}

export function ResultFootprintPreview({ bbox }: ResultFootprintPreviewProps) {
  if (!bbox) {
    return <div className="text-xs text-gray-500">No bbox</div>
  }

  return (
    <div className="text-[10px] leading-tight text-gray-600 bg-gray-50 border border-gray-200 rounded p-2 min-w-[140px]">
      <div className="font-semibold text-gray-700 mb-1">Footprint</div>
      <div>minX: {bbox[0].toFixed(2)}</div>
      <div>minY: {bbox[1].toFixed(2)}</div>
      <div>maxX: {bbox[2].toFixed(2)}</div>
      <div>maxY: {bbox[3].toFixed(2)}</div>
    </div>
  )
}
