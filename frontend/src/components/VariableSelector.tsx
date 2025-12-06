/**
 * Variable selector component for choosing which variable to extract timeseries for
 */

import { useState, useEffect } from 'react';
import type { Dataset } from '../types';

interface VariableSelectorProps {
  dataset: Dataset | null;
  selectedVariable: string | null;
  onVariableSelect: (variable: string) => void;
}

export function VariableSelector({
  dataset,
  selectedVariable,
  onVariableSelect,
}: VariableSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);

  // Auto-select first variable when dataset changes
  useEffect(() => {
    if (dataset && dataset.variables && dataset.variables.length > 0 && !selectedVariable) {
      onVariableSelect(dataset.variables[0].name);
    }
  }, [dataset, selectedVariable, onVariableSelect]);

  if (!dataset || !dataset.variables || dataset.variables.length === 0) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-md px-3 py-2">
        <p className="text-sm text-gray-500">No variables available</p>
      </div>
    );
  }

  const selectedVar = dataset.variables.find(v => v.name === selectedVariable);

  return (
    <div className="relative">
      <label className="block text-sm font-medium text-gray-700 mb-1">
        Variable
      </label>
      
      {/* Dropdown button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-full bg-white border border-gray-300 rounded-md px-3 py-2 text-left focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent hover:border-gray-400 transition-colors"
      >
        <div className="flex items-center justify-between">
          <div className="flex-1 min-w-0">
            {selectedVar ? (
              <div>
                <p className="text-sm font-medium text-gray-900 truncate">
                  {selectedVar.name}
                </p>
                <p className="text-xs text-gray-500 truncate">
                  {selectedVar.longName} ({selectedVar.units})
                </p>
              </div>
            ) : (
              <p className="text-sm text-gray-500">Select a variable</p>
            )}
          </div>
          <svg
            className={`w-5 h-5 flex-shrink-0 text-gray-400 transition-transform ${isOpen ? 'rotate-180' : ''}`}
            style={{ width: '1.25rem', height: '1.25rem', flexShrink: 0 }}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M19 9l-7 7-7-7"
            />
          </svg>
        </div>
      </button>

      {/* Dropdown menu */}
      {isOpen && (
        <>
          {/* Click outside to close */}
          <div
            className="fixed inset-0 z-0"
            onClick={() => setIsOpen(false)}
          />
          <div className="absolute z-20 w-full mt-1 bg-white border border-gray-300 rounded-md shadow-lg max-h-60 overflow-auto">
            {dataset.variables.map((variable) => (
              <button
                key={variable.name}
                onClick={() => {
                  onVariableSelect(variable.name);
                  setIsOpen(false);
                }}
                className={`w-full text-left px-3 py-2 hover:bg-gray-50 transition-colors ${
                  selectedVariable === variable.name ? 'bg-blue-50 text-blue-900' : 'text-gray-900'
                }`}
              >
                <div>
                  <p className="text-sm font-medium">{variable.name}</p>
                  <p className="text-xs text-gray-500">
                    {variable.longName} ({variable.units})
                  </p>
                  {variable.description && (
                    <p className="text-xs text-gray-400 mt-1 line-clamp-2">
                      {variable.description}
                    </p>
                  )}
                </div>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
