const APIKEY: &str = "IB1-APIKEYHERE";
const PLATFORM: &str = "roblox";
const AGGRESSIVEOPTIMIZATIONS: &str = "0";
const INTENSEVMSCRAMBLING: &str = "false";
const ENABLEVMCOMPRESSION: &str = "false";
const MAXWAIT: u64 = 240;
const RETRYDELAY: u64 = 5;
const MAXFAILS: u64 = 3;

use anyhow::{Context, Result, bail};
use reqwest::Url;
use reqwest::blocking::Client;
use std::fs;
use std::thread;
use std::time::Duration;

fn main() -> Result<()> {
    let base = Url::parse("https://ironbrew1.com")?;
    let client = Client::new();

    let url = Url::parse_with_params(
        "https://ironbrew1.com/obfuscate",
        &[
            ("platform", PLATFORM),
            ("aggressiveOptimizations", AGGRESSIVEOPTIMIZATIONS),
            ("intenseVmScrambling", INTENSEVMSCRAMBLING),
            ("enableVmCompression", ENABLEVMCOMPRESSION),
        ],
    )?;

    let response = client
        .post(url)
        .header("Key", APIKEY)
        .body(fs::read("input.lua").context("Unable to read input.lua")?)
        .send()?;

    if !response.status().is_success() {
        bail!("Unable to queue obfuscation: {}", response.status());
    }

    let t: serde_json::Value = response.json().context("Unable to decode JSON")?;

    println!("Obfuscation started with GUID: {}", t["uploadGuid"]);

    let status_url = base.join(t["statusUrl"].as_str().context("Response is missing statusUrl")?)?;

    let mut elapsedtime = 0;
    let mut failcount = 0;
    let mut waittime = 0;

    loop {
        waittime += RETRYDELAY;
        thread::sleep(Duration::from_secs(waittime));
        elapsedtime += waittime;

        let response = client.get(status_url.clone()).header("Key", APIKEY).send()?;

        if !response.status().is_success() {
            failcount += 1;
            println!("Status check failed with status: {} ({}/{})", response.status(), failcount, MAXFAILS);
            if failcount >= MAXFAILS || elapsedtime >= MAXWAIT {
                bail!("Obfuscation failed (fails: {} | elapsed time: {})", failcount, elapsedtime);
            }
            continue;
        }

        let rsp: serde_json::Value = response.json().context("Unable to decode JSON")?;

        if rsp["status"] == "completed" {
            println!("Obfuscation completed in {} seconds", elapsedtime);
            let download_url = base.join(rsp["downloadUrl"].as_str().context("Response is missing downloadUrl")?)?;
            let response = client.get(download_url).header("Key", APIKEY).send()?;
            if !response.status().is_success() {
                bail!("Download failed with status: {}", response.status());
            }
            fs::write("output.lua", response.bytes()?)?;
            return Ok(());
        } else if rsp["status"] == "failed" || elapsedtime >= MAXWAIT {
            bail!("Obfuscation failed (status: {} | elapsed time: {})", rsp["status"], elapsedtime);
        }

        println!("Obfuscation is still in progress. Elapsed time: {} seconds. Checking again in {} seconds.", elapsedtime, RETRYDELAY + waittime);
    }
}
