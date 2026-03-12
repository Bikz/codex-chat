import * as React from 'react';
import { cn } from '@/lib/utils';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'default' | 'primary' | 'ghost';
  size?: 'default' | 'sm' | 'icon';
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { className, variant = 'default', size = 'default', ...props },
  ref
) {
  return (
    <button
      ref={ref}
      className={cn(
        'inline-flex items-center justify-center whitespace-nowrap rounded-xl font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent disabled:pointer-events-none disabled:opacity-50',
        variant === 'default' && 'bg-surface-alt border border-line text-fg hover:bg-surface-subtle',
        variant === 'primary' && 'bg-accent text-accent-fg border border-accent hover:opacity-90 shadow-sm',
        variant === 'ghost' && 'bg-transparent text-fg hover:bg-surface-alt',
        size === 'default' && 'min-h-[44px] px-4 py-2 text-[15px]',
        size === 'sm' && 'min-h-[36px] px-3 text-sm rounded-lg',
        size === 'icon' && 'h-11 w-11 rounded-full',
        className
      )}
      {...props}
    />
  );
});
