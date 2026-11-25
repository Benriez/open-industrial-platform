use crate::DataSourceId;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct HueLightsQuery {
    pub source: DataSourceId,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct HueLight {
    pub id: u64,
    pub name: String,
    pub kind: String,
    pub reachable: Option<bool>,
    pub on: bool,
    pub brightness_percent: Option<f64>,
    pub hue_degrees: Option<f64>,
    pub saturation_percent: Option<f64>,
    pub ct: Option<u16>,
    pub ct_range: Option<[u16; 2]>,
    pub color_mode: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct HueLights {
    pub source: DataSourceId,
    pub can_control: bool,
    pub lights: Vec<HueLight>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum HueChange {
    Power { on: bool },
    Brightness { percent: u8 },
    Color { degrees: u16, saturation: u8 },
    Temperature { mired: u16 },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct HueLightCommand {
    pub source: DataSourceId,
    pub light_id: u64,
    pub change: HueChange,
}
