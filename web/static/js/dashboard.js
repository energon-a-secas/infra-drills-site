/**
 * Dashboard JavaScript - Local Drills Web Interface
 * Handles drill interactions and progress updates
 */

// Global state
let progressData = {};

/**
 * Initialize dashboard
 */
document.addEventListener('DOMContentLoaded', async () => {
    console.log('Local Drills Dashboard loaded');
    await loadProgress();
    startAutoRefresh();
});

/**
 * Load progress from API
 */
async function loadProgress() {
    try {
        const response = await fetch('/api/progress');
        progressData = await response.json();
        updateProgressDisplay();
    } catch (error) {
        console.error('Failed to load progress:', error);
    }
}

/**
 * Update progress display
 */
function updateProgressDisplay() {
    // Update stat cards if elements exist
    const totalEl = document.querySelector('.stat-card:nth-child(1) .stat-number');
    const completedEl = document.querySelector('.stat-card:nth-child(2) .stat-number');
    const percentageEl = document.querySelector('.stat-card:nth-child(3) .stat-number');

    if (totalEl) totalEl.textContent = progressData.total || 0;
    if (completedEl) completedEl.textContent = progressData.completed || 0;
    if (percentageEl) percentageEl.textContent = `${progressData.percentage || 0}%`;
}

/**
 * Mark drill as completed
 */
async function markCompleted(drillPath) {
    try {
        const response = await fetch('/api/mark-drill-status', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                drill_path: drillPath,
                status: 'completed'
            })
        });

        if (response.ok) {
            console.log(`✅ Marked ${drillPath} as completed`);

            // Show visual feedback
            showNotification('✅ Drill marked as completed!', 'success');

            // Refresh progress
            await loadProgress();
        } else {
            throw new Error('Failed to mark completed');
        }
    } catch (error) {
        console.error('Mark completed error:', error);
        showNotification('❌ Failed to update progress', 'error');
    }
}

/**
 * Show notification
 */
function showNotification(message, type = 'info') {
    // Remove existing notifications
    const existing = document.querySelector('.notification');
    if (existing) {
        existing.remove();
    }

    // Create notification
    const notification = document.createElement('div');
    notification.className = `notification notification-${type}`;
    notification.textContent = message;

    // Style it
    Object.assign(notification.style, {
        position: 'fixed',
        top: '20px',
        right: '20px',
        padding: '12px 20px',
        background: type === 'success' ? '#00a86b' : type === 'error' ? '#ff453a' : '#0063e5',
        color: 'white',
        borderRadius: '6px',
        zIndex: '1000',
        fontWeight: '500',
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.3)'
    });

    document.body.appendChild(notification);

    // Auto-remove after 3 seconds
    setTimeout(() => {
        if (notification.parentNode) {
            notification.remove();
        }
    }, 3000);
}

/**
 * Auto-refresh progress
 */
function startAutoRefresh() {
    setInterval(loadProgress, 30000); // Refresh every 30 seconds
    console.log('Auto-refresh started (30s interval)');
}

/**
 * Keyboard shortcuts
 */
document.addEventListener('keydown', (e) => {
    // Ctrl+T to open terminal (handled in drill.html)
    // Ctrl+D for dashboard
    if (e.ctrlKey && e.key === 'd') {
        e.preventDefault();
        window.open('/', '_self');
    }
    // Ctrl+Q for quiz
    if (e.ctrlKey && e.key === 'q') {
        e.preventDefault();
        window.open('/quiz', '_self');
    }
});

// Export for global access
window.DrillDashboard = {
    loadProgress,
    markCompleted,
    showNotification
};
