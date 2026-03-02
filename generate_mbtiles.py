#!/usr/bin/env python3
"""
Offline MBTiles Generator using Tilemaker
==========================================

This script generates vector MBTiles from pre-downloaded OSM data.
It DOES NOT download anything and will fail if required files are missing.

Requirements:
- tilemaker binary installed on system (check with: tilemaker --help)
- Pre-downloaded OSM PBF data file
- Pre-downloaded tilemaker configuration files

Usage:
    python3 generate_mbtiles.py
    python3 generate_mbtiles.py --input data/custom.osm.pbf
"""

import os
import sys
import subprocess
import logging
import argparse
import shutil
import glob
from pathlib import Path
from datetime import datetime

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def find_first_pbf(data_dir: str = "data") -> str:
    """Find the first .osm.pbf file in the data directory.
    
    Args:
        data_dir: Directory to search for PBF files
        
    Returns:
        Path to first PBF file found, or default path if none found
    """
    pbf_files = glob.glob(os.path.join(data_dir, "*.osm.pbf"))
    if pbf_files:
        return pbf_files[0]
    return os.path.join(data_dir, "region-latest.osm.pbf")


def find_all_pbf(data_dir: str = "data") -> list:
    """Find all .osm.pbf files in the data directory.
    
    Args:
        data_dir: Directory to search for PBF files
        
    Returns:
        List of paths to all PBF files found (sorted)
    """
    pbf_files = glob.glob(os.path.join(data_dir, "*.osm.pbf"))
    return sorted(pbf_files)


def derive_output_name(output_dir: str = "mbtiles-output") -> str:
    return os.path.join(output_dir, f"region.mbtiles")


class MBTilesGenerator:
    """Handles offline MBTiles generation using tilemaker."""
    
    def __init__(self, 
                 input_pbf: str = None,
                 output_mbtiles: str = None,
                 config_json: str = "tilemaker/config-openmaptiles.json",
                 process_lua: str = "tilemaker/process-openmaptiles.lua",
                 merge_mode: bool = False):
        """
        Initialize the MBTiles generator.
        
        Args:
            input_pbf: Path to input OSM PBF file (auto-detected if None)
            output_mbtiles: Path to output MBTiles file (auto-derived if None)
            config_json: Path to tilemaker config JSON
            process_lua: Path to tilemaker process Lua script
            merge_mode: If True, merge all PBF files in data/ into one before generating
        """
        self.merge_mode = merge_mode
        # Auto-detect input if not provided
        if input_pbf is None:
            input_pbf = find_first_pbf()
            logger.info(f"Auto-detected input PBF: {input_pbf}")
        
        # Normalize Docker-style absolute paths to relative paths
        # Convert paths like /app/data/file.pbf to data/file.pbf
        input_pbf = self._normalize_path(input_pbf)
        if output_mbtiles is not None:
            output_mbtiles = self._normalize_path(output_mbtiles)
        config_json = self._normalize_path(config_json)
        process_lua = self._normalize_path(process_lua)
        
        # Auto-derive output if not provided
        if output_mbtiles is None:
            output_mbtiles = derive_output_name()
            logger.info(f"Auto-derived output MBTiles: {output_mbtiles}")
        
        self.input_pbf = Path(input_pbf)
        self.output_mbtiles = Path(output_mbtiles)
        self.config_json = Path(config_json)
        self.process_lua = Path(process_lua)
    
    @staticmethod
    def _normalize_path(path: str) -> str:
        """
        Normalize Docker-style absolute paths to relative paths.
        
        Converts paths like /app/data/file.pbf to data/file.pbf
        Handles both Unix and Windows paths.
        
        Args:
            path: Input path string
            
        Returns:
            Normalized path string
        """
        if not path:
            return path
        
        original_path = path
        
        # Convert backslashes to forward slashes for consistency
        path = path.replace('\\', '/')
        
        return path
        
    def validate_tilemaker_installed(self) -> bool:
        """Check if tilemaker binary is available on system."""
        logger.info("Checking for tilemaker binary...")
        
        tilemaker_path = shutil.which("tilemaker")
        if not tilemaker_path:
            logger.error("❌ tilemaker binary not found in PATH")
            logger.error("Install tilemaker from: https://github.com/systemed/tilemaker")
            logger.error("Or via package manager (e.g., brew install tilemaker)")
            return False
            
        logger.info(f"✅ Found tilemaker at: {tilemaker_path}")
        
        # Get version
        try:
            result = subprocess.run(
                ["tilemaker", "--help"],
                capture_output=True,
                text=True,
                timeout=5
            )
            logger.info("✅ tilemaker is executable")
            return True
        except Exception as e:
            logger.error(f"❌ tilemaker found but not executable: {e}")
            return False
    
    def validate_required_files(self) -> bool:
        """Validate all required files exist before generation."""
        logger.info("Validating required files...")
        
        files_to_check = [
            (self.input_pbf, "OSM PBF input data"),
            (self.config_json, "Tilemaker config JSON"),
            (self.process_lua, "Tilemaker process Lua script")
        ]
        
        all_valid = True
        for file_path, description in files_to_check:
            if not file_path.exists():
                logger.error(f"❌ Missing: {description}")
                logger.error(f"   Expected at: {file_path.absolute()}")
                
                # Debug: Show what's actually in the parent directory
                parent_dir = file_path.parent
                logger.error(f"   Checking parent directory: {parent_dir.absolute()}")
                if parent_dir.exists():
                    try:
                        contents = list(parent_dir.iterdir())
                        logger.error(f"   Directory contents ({len(contents)} items):")
                        for item in sorted(contents)[:20]:  # Show first 20 items
                            item_type = "DIR" if item.is_dir() else "FILE"
                            size = f"{item.stat().st_size / (1024*1024):.2f} MB" if item.is_file() else ""
                            logger.error(f"     [{item_type}] {item.name} {size}")
                        if len(contents) > 20:
                            logger.error(f"     ... and {len(contents) - 20} more items")
                    except Exception as e:
                        logger.error(f"   Could not list directory: {e}")
                else:
                    logger.error(f"   Parent directory does not exist!")
                
                all_valid = False
            elif not file_path.is_file():
                logger.error(f"❌ Not a file: {description}")
                logger.error(f"   Path: {file_path.absolute()}")
                all_valid = False
            else:
                size_mb = file_path.stat().st_size / (1024 * 1024)
                logger.info(f"✅ Found: {description} ({size_mb:.2f} MB)")
        
        return all_valid
    
    def validate_output_directory(self) -> bool:
        """Ensure output directory exists and is writable."""
        logger.info("Validating output directory...")
        
        output_dir = self.output_mbtiles.parent
        
        # Create directory if it doesn't exist
        if not output_dir.exists():
            try:
                output_dir.mkdir(parents=True, exist_ok=True)
                logger.info(f"✅ Created output directory: {output_dir.absolute()}")
            except Exception as e:
                logger.error(f"❌ Failed to create output directory: {e}")
                return False
        
        # Check if writable
        if not os.access(output_dir, os.W_OK):
            logger.error(f"❌ Output directory not writable: {output_dir.absolute()}")
            return False
        
        logger.info(f"✅ Output directory writable: {output_dir.absolute()}")
        return True
    
    def merge_pbf_files(self, data_dir: str = "data") -> Path:
        """
        Merge all PBF files in data directory into a single merged PBF file using osmconvert.
        Uses the approach: osmconvert region1.pbf --out-o5m | osmconvert - region2.pbf -o=all.pbf
        
        Args:
            data_dir: Directory containing PBF files
            
        Returns:
            Path to merged PBF file
        """
        logger.info("=" * 60)
        logger.info("Merging PBF files")
        logger.info("=" * 60)
        
        # Find all PBF files
        pbf_files = find_all_pbf(data_dir)
        
        if not pbf_files:
            logger.error(f"❌ No PBF files found in {data_dir}/")
            sys.exit(1)
        
        if len(pbf_files) == 1:
            logger.info(f"Only one PBF file found, skipping merge: {pbf_files[0]}")
            return Path(pbf_files[0])
        
        logger.info(f"Found {len(pbf_files)} PBF files to merge:")
        total_size = 0
        for pbf in pbf_files:
            size_mb = Path(pbf).stat().st_size / (1024 * 1024)
            total_size += size_mb
            logger.info(f"  - {pbf} ({size_mb:.2f} MB)")
        logger.info(f"Total input size: {total_size:.2f} MB")
        logger.info("")
        
        # Check if osmconvert is available
        osmconvert_path = shutil.which("osmconvert")
        if not osmconvert_path:
            logger.error("❌ osmconvert not found in PATH")
            logger.error("Install osmctools: apt-get install osmctools (or brew install osmctools on macOS)")
            sys.exit(1)
        
        # Create merged output file
        merged_output = Path(data_dir) / "merged-regions.osm.pbf"
        
        logger.info("Merging files using osmconvert with o5m intermediate format...")
        logger.info("This may take several minutes...")
        logger.info("")
        
        start_time = datetime.now()
        
        try:
            # For 2 files: osmconvert region1.pbf --out-o5m | osmconvert - region2.pbf -o=all.pbf
            # For 3+ files, we chain: file1 -> o5m -> merge with file2 -> o5m -> merge with file3 -> pbf
            
            if len(pbf_files) == 2:
                # Simple case: 2 files
                cmd = f'osmconvert "{pbf_files[0]}" --out-o5m | osmconvert - "{pbf_files[1]}" -o="{merged_output}"'
                logger.info(f"Running: {cmd}")
                
                result = subprocess.run(
                    cmd,
                    shell=True,
                    capture_output=True,
                    text=True,
                    check=True
                )
            else:
                # Multiple files: chain them together
                # Start with first file, convert to o5m, then iteratively merge with remaining files
                temp_files = []
                current_input = pbf_files[0]
                
                for i, next_file in enumerate(pbf_files[1:], 1):
                    if i < len(pbf_files) - 1:
                        # Intermediate merge to temp file in /tmp (stays inside container)
                        temp_output = Path("/tmp") / f"temp_merge_{i}.o5m"
                        temp_files.append(temp_output)
                        cmd = f'osmconvert "{current_input}" --out-o5m | osmconvert - "{next_file}" --out-o5m -o="{temp_output}"'
                        logger.info(f"Step {i}/{len(pbf_files)-1}: Merging with {os.path.basename(next_file)}")
                    else:
                        # Final merge to pbf
                        cmd = f'osmconvert "{current_input}" --out-o5m | osmconvert - "{next_file}" -o="{merged_output}"'
                        logger.info(f"Step {i}/{len(pbf_files)-1}: Final merge with {os.path.basename(next_file)}")
                    
                    result = subprocess.run(
                        cmd,
                        shell=True,
                        capture_output=True,
                        text=True,
                        check=True
                    )
                    
                    if i < len(pbf_files) - 1:
                        current_input = temp_output
                
                # Clean up temp files
                for temp_file in temp_files:
                    if temp_file.exists():
                        temp_file.unlink()
                        logger.debug(f"Removed temp file: {temp_file}")
            
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            if merged_output.exists():
                merged_size = merged_output.stat().st_size / (1024 * 1024)
                logger.info("✅ PBF files merged successfully!")
                logger.info(f"Merged file: {merged_output}")
                logger.info(f"Merged size: {merged_size:.2f} MB")
                logger.info(f"Duration: {duration:.1f} seconds")
                logger.info("")
                return merged_output
            else:
                logger.error("❌ Merge failed: output file not created")
                sys.exit(1)
                
        except subprocess.CalledProcessError as e:
            logger.error(f"❌ osmconvert merge failed: {e}")
            if e.stderr:
                logger.error(f"stderr: {e.stderr}")
            if e.stdout:
                logger.error(f"stdout: {e.stdout}")
            sys.exit(1)
        except Exception as e:
            logger.error(f"❌ Unexpected error during merge: {e}")
            import traceback
            logger.error(traceback.format_exc())
            sys.exit(1)
    
    def generate_mbtiles(self) -> bool:
        """
        Run tilemaker to generate MBTiles file.
        
        Returns:
            True if generation successful, False otherwise
        """
        logger.info("=" * 60)
        logger.info("Starting MBTiles generation")
        logger.info("=" * 60)
        
        # Build tilemaker command
        cmd = [
            "tilemaker",
            "--input", str(self.input_pbf.absolute()),
            "--output", str(self.output_mbtiles.absolute()),
            "--config", str(self.config_json.absolute()),
            "--process", str(self.process_lua.absolute())
        ]
        
        logger.info(f"Command: {' '.join(cmd)}")
        logger.info("")
        logger.info("This may take several minutes depending on data size...")
        logger.info("Expected time: 5-30 minutes depending on region size")
        logger.info("")
        
        start_time = datetime.now()
        
        try:
            # Run tilemaker with live output
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            # Stream output in real-time
            for line in process.stdout:
                print(line, end='')
            
            # Wait for completion
            return_code = process.wait()
            
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            if return_code == 0:
                logger.info("=" * 60)
                logger.info("✅ MBTiles generation completed successfully!")
                logger.info("=" * 60)
                logger.info(f"Duration: {duration:.1f} seconds ({duration/60:.1f} minutes)")
                
                if self.output_mbtiles.exists():
                    size_mb = self.output_mbtiles.stat().st_size / (1024 * 1024)
                    logger.info(f"Output file: {self.output_mbtiles.absolute()}")
                    logger.info(f"Output size: {size_mb:.2f} MB")
                
                return True
            else:
                logger.error("=" * 60)
                logger.error(f"❌ MBTiles generation failed with code {return_code}")
                logger.error("=" * 60)
                return False
                
        except FileNotFoundError:
            logger.error("❌ tilemaker command not found")
            return False
        except subprocess.TimeoutExpired:
            logger.error("❌ Tilemaker process timed out")
            return False
        except KeyboardInterrupt:
            logger.warning("⚠️  Process interrupted by user")
            return False
        except Exception as e:
            logger.error(f"❌ Unexpected error during generation: {e}")
            return False
    
    def run(self) -> bool:
        """
        Execute the complete validation and generation pipeline.
        
        Returns:
            True if successful, False otherwise
        """
        logger.info("Offline MBTiles Generator")
        logger.info("=" * 60)
        logger.info("")
        
        # If merge mode is enabled, merge all PBF files first
        merged_pbf_to_cleanup = None
        if self.merge_mode:
            merged_pbf = self.merge_pbf_files("data")
            # Track for cleanup only if a new merged file was created (not a returned single original file)
            if merged_pbf.name == "merged-regions.osm.pbf":
                merged_pbf_to_cleanup = merged_pbf
            # Update input to use merged file
            self.input_pbf = merged_pbf
        # Debug: Show current working directory and data location
        logger.info(f"Current working directory: {Path.cwd()}")
        logger.info(f"Looking for input at: {self.input_pbf.absolute()}")
        logger.info("")
        
        # Debug: List data directory contents (both relative and absolute paths)
        for check_path in [Path("data"), Path("/app/data")]:
            if check_path.exists():
                logger.info(f"Contents of '{check_path}' directory:")
                try:
                    items = list(check_path.iterdir())
                    if len(items) == 0:
                        logger.warning(f"  Directory is EMPTY!")
                    else:
                        for item in sorted(items):
                            item_type = "DIR" if item.is_dir() else "FILE"
                            size = f"{item.stat().st_size / (1024*1024):.2f} MB" if item.is_file() else ""
                            logger.info(f"  [{item_type}] {item.name} {size}")
                except Exception as e:
                    logger.error(f"  Error listing: {e}")
            else:
                logger.warning(f"'{check_path}' directory does not exist!")
        logger.info("")
        
        # Step 1: Check tilemaker binary
        if not self.validate_tilemaker_installed():
            return False
        logger.info("")
        
        # Step 2: Validate required files
        if not self.validate_required_files():
            logger.error("")
            logger.error("Fix missing files and try again.")
            logger.error("This script DOES NOT download anything automatically.")
            return False
        logger.info("")
        
        # Step 3: Validate output directory
        if not self.validate_output_directory():
            return False
        logger.info("")
        
        # Step 4: Generate MBTiles
        success = self.generate_mbtiles()

        # Clean up intermediate merged PBF now that mbtiles have been created
        if success and merged_pbf_to_cleanup and merged_pbf_to_cleanup.exists():
            try:
                merged_pbf_to_cleanup.unlink()
                logger.info(f"🗑️  Deleted intermediate merged PBF: {merged_pbf_to_cleanup}")
            except Exception as e:
                logger.warning(f"⚠️  Could not delete intermediate merged PBF: {e}")

        if success:
            logger.info("")
            logger.info("Next steps:")
            logger.info("  1. Start TileServer-GL:")
            logger.info(f"     tileserver-gl-light {self.output_mbtiles.absolute()}")
            logger.info("  2. View in browser:")
            logger.info("     http://localhost:8080")
        
        return success


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Generate vector MBTiles from pre-downloaded OSM data",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-detect first PBF file in data/ folder
  python3 generate_mbtiles.py
  
  # Merge all PBF files into one mbtiles (recommended for TileServer)
  python3 generate_mbtiles.py --merge
  # OR
  python3 generate_mbtiles.py --all
  
  # Custom input file (single file)
  python3 generate_mbtiles.py --input data/belgium.osm.pbf --output mbtiles-output/belgium.mbtiles
  
  # Custom configuration
  python3 generate_mbtiles.py --config custom-config.json --process custom-process.lua

Note: This script works 100%% offline and will NOT download anything.
        """
    )
    
    parser.add_argument(
        "--merge",
        action="store_true",
        help="Merge ALL .osm.pbf files in data/ into one before generating mbtiles (recommended for TileServer)"
    )
    
    parser.add_argument(
        "--all",
        action="store_true",
        help="Same as --merge: Merge ALL .osm.pbf files in data/ into one mbtiles (alias for backward compatibility)"
    )
    
    parser.add_argument(
        "--input",
        default=None,
        help="Path to input OSM PBF file (default: auto-detect first .osm.pbf in data/)"
    )
    
    parser.add_argument(
        "--output",
        default=None,
        help="Path to output MBTiles file (default: auto-derive from input filename)"
    )
    
    parser.add_argument(
        "--config",
        default="tilemaker/config-openmaptiles.json",
        help="Path to tilemaker config JSON (default: tilemaker/config-openmaptiles.json)"
    )
    
    parser.add_argument(
        "--process",
        default="tilemaker/process-openmaptiles.lua",
        help="Path to tilemaker process Lua script (default: tilemaker/process-openmaptiles.lua)"
    )
    
    args = parser.parse_args()
    
    # Debug: Show raw arguments received from argparse
    logger.debug(f"Raw args.merge: {args.merge}")
    logger.debug(f"Raw args.all: {args.all}")
    logger.debug(f"Raw args.input: {args.input}")
    logger.debug(f"Raw args.output: {args.output}")
    logger.debug(f"Raw args.config: {args.config}")
    logger.debug(f"Raw args.process: {args.process}")
    
    # Both --merge and --all do the same thing now (merge all PBF files)
    if args.merge or args.all:
        logger.info("MERGE MODE: Merging all PBF files into one mbtiles")
        logger.info("=" * 60)
        logger.info("")
        
        generator = MBTilesGenerator(
            input_pbf=args.input,
            output_mbtiles=args.output,
            config_json=args.config,
            process_lua=args.process,
            merge_mode=True
        )
        
        success = generator.run()
        sys.exit(0 if success else 1)
    
    # Single file processing (original behavior)
    else:
        generator = MBTilesGenerator(
            input_pbf=args.input,
            output_mbtiles=args.output,
            config_json=args.config,
            process_lua=args.process
        )
        
        success = generator.run()
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
