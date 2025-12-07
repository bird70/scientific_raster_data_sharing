import type { TimeseriesData } from '@/types'

interface DownloadCsvButtonProps {
  data: TimeseriesData | null
  onDownload: () => void
}

export function DownloadCsvButton({ data, onDownload }: DownloadCsvButtonProps) {
  const disabled = !data || data.times.length === 0
  return (
    <button
      type="button"
      className="px-3 py-2 text-sm bg-white border border-gray-300 rounded-md shadow-sm hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
      onClick={onDownload}
      disabled={disabled}
      aria-label="Download timeseries as CSV"
    >
      Download CSV
    </button>
  )
}
