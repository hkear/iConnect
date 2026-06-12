// iConnect Device Registry - Approval workflow
// Devices register via heartbeat, admin approves/rejects via Web UI

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::RwLock;
use serde::{Deserialize, Serialize};
use axum::{
    Json, Router,
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post, delete},
};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum DeviceStatus {
    Pending,   // Waiting for admin approval
    Approved,  // Approved and can connect
    Rejected,  // Rejected by admin
    Online,    // Approved and currently connected
    Offline,   // Approved but disconnected
}

impl std::fmt::Display for DeviceStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DeviceStatus::Pending => write!(f, "pending"),
            DeviceStatus::Approved => write!(f, "approved"),
            DeviceStatus::Rejected => write!(f, "rejected"),
            DeviceStatus::Online => write!(f, "online"),
            DeviceStatus::Offline => write!(f, "offline"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub id: String,            // UUID
    pub machine_id: String,    // Hardware device ID
    pub hostname: String,      // Device hostname
    pub status: DeviceStatus,
    pub assigned_ip: Option<String>,  // Virtual IP assigned by admin
    pub alias: Option<String>,        // Admin-set device alias
    pub created_at: String,           // ISO 8601 timestamp
    pub last_seen: Option<String>,    // Last heartbeat time
    pub version: Option<String>,      // Client version
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApproveDeviceRequest {
    pub assigned_ip: Option<String>,
    pub alias: Option<String>,
}

pub struct DeviceRegistry {
    devices: RwLock<HashMap<String, DeviceInfo>>,
}

impl DeviceRegistry {
    pub fn new() -> Self {
        let mut devices = HashMap::new();
        // Create a default pre-approved device for the server itself
        devices.insert("server-self".to_string(), DeviceInfo {
            id: "server-self".to_string(),
            machine_id: "server".to_string(),
            hostname: "iConnect Server".to_string(),
            status: DeviceStatus::Online,
            assigned_ip: Some("10.144.0.1".to_string()),
            alias: Some("Core Server".to_string()),
            created_at: chrono::Utc::now().to_rfc3339(),
            last_seen: Some(chrono::Utc::now().to_rfc3339()),
            version: Some("1.0.0".to_string()),
        });
        Self {
            devices: RwLock::new(devices),
        }
    }

    /// Register a new device (called when a new client heartbeat is received)
    pub fn register_device(&self, machine_id: &str, hostname: &str, version: Option<&str>) -> String {
        let mut devices = self.devices.write().unwrap();
        // Check if already registered
        let existing_id = {
            let mut found = None;
            for (id, dev) in devices.iter() {
                if dev.machine_id == machine_id {
                    found = Some(id.clone());
                    break;
                }
            }
            found
        };
        if let Some(existing_id) = existing_id {
            if let Some(dev) = devices.get_mut(&existing_id) {
                dev.last_seen = Some(chrono::Utc::now().to_rfc3339());
            }
            return existing_id;
        }
        // New device - add as pending
        let id = Uuid::new_v4().to_string();
        devices.insert(id.clone(), DeviceInfo {
            id: id.clone(),
            machine_id: machine_id.to_string(),
            hostname: hostname.to_string(),
            status: DeviceStatus::Pending,
            assigned_ip: None,
            alias: None,
            created_at: chrono::Utc::now().to_rfc3339(),
            last_seen: Some(chrono::Utc::now().to_rfc3339()),
            version: version.map(|v| v.to_string()),
        });
        id
    }

    /// Update device online status (called on heartbeat)
    pub fn set_online(&self, machine_id: &str, online: bool) {
        let mut devices = self.devices.write().unwrap();
        for (_, dev) in devices.iter_mut() {
            if dev.machine_id == machine_id && dev.status == DeviceStatus::Approved {
                dev.status = if online { DeviceStatus::Online } else { DeviceStatus::Offline };
            }
        }
    }

    /// Approve a pending device
    pub fn approve(&self, device_id: &str, ip: Option<String>, alias: Option<String>) -> Result<(), String> {
        let mut devices = self.devices.write().unwrap();
        let dev = devices.get_mut(device_id).ok_or("Device not found".to_string())?;
        if dev.status != DeviceStatus::Pending {
            return Err("Device is not in pending state".to_string());
        }
        dev.status = DeviceStatus::Approved;
        dev.assigned_ip = ip.or(dev.assigned_ip.take());
        dev.alias = alias.or(dev.alias.take());
        Ok(())
    }

    /// Reject a pending device
    pub fn reject(&self, device_id: &str) -> Result<(), String> {
        let mut devices = self.devices.write().unwrap();
        let dev = devices.get_mut(device_id).ok_or("Device not found".to_string())?;
        dev.status = DeviceStatus::Rejected;
        Ok(())
    }

    /// Kick an online device
    pub fn kick(&self, device_id: &str) -> Result<(), String> {
        let mut devices = self.devices.write().unwrap();
        let dev = devices.get_mut(device_id).ok_or("Device not found".to_string())?;
        if dev.status != DeviceStatus::Online {
            return Err("Device is not online".to_string());
        }
        dev.status = DeviceStatus::Offline;
        Ok(())
    }

    /// List all devices
    pub fn list_devices(&self) -> Vec<DeviceInfo> {
        self.devices.read().unwrap().values().cloned().collect()
    }

    /// Get pending devices
    pub fn list_pending(&self) -> Vec<DeviceInfo> {
        self.devices.read().unwrap().values()
            .filter(|d| d.status == DeviceStatus::Pending)
            .cloned()
            .collect()
    }

    /// Get a single device by ID
    pub fn get_device(&self, device_id: &str) -> Option<DeviceInfo> {
        self.devices.read().unwrap().get(device_id).cloned()
    }
}

pub type SharedDeviceRegistry = Arc<DeviceRegistry>;

// --- API Handlers ---

async fn handle_list_devices(
    State(registry): State<SharedDeviceRegistry>,
) -> Json<Vec<DeviceInfo>> {
    Json(registry.list_devices())
}

async fn handle_list_pending(
    State(registry): State<SharedDeviceRegistry>,
) -> Json<Vec<DeviceInfo>> {
    Json(registry.list_pending())
}

async fn handle_approve_device(
    State(registry): State<SharedDeviceRegistry>,
    Path(device_id): Path<String>,
    Json(req): Json<ApproveDeviceRequest>,
) -> Result<Json<DeviceInfo>, (StatusCode, String)> {
    registry.approve(&device_id, req.assigned_ip, req.alias)
        .map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    let dev = registry.get_device(&device_id)
        .ok_or((StatusCode::NOT_FOUND, "Device not found".to_string()))?;
    Ok(Json(dev))
}

async fn handle_reject_device(
    State(registry): State<SharedDeviceRegistry>,
    Path(device_id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    registry.reject(&device_id).map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    Ok(StatusCode::NO_CONTENT)
}

async fn handle_kick_device(
    State(registry): State<SharedDeviceRegistry>,
    Path(device_id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    registry.kick(&device_id).map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    Ok(StatusCode::NO_CONTENT)
}

/// Build the device management API routes
pub fn router() -> Router<SharedDeviceRegistry> {
    Router::new()
        .route("/api/v1/devices", get(handle_list_devices))
        .route("/api/v1/devices/pending", get(handle_list_pending))
        .route("/api/v1/devices/:id/approve", post(handle_approve_device))
        .route("/api/v1/devices/:id/reject", post(handle_reject_device))
        .route("/api/v1/devices/:id/kick", post(handle_kick_device))
}
