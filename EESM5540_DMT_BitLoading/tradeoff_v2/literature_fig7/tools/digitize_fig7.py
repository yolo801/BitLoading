#!/usr/bin/env python3
"""Digitize the native blue trace of Zhong et al. (2015), Fig. 7."""

import argparse
import csv
import hashlib
import json
from pathlib import Path

import fitz
import numpy as np


DOI = "10.1364/OE.23.001176"
PDF_SHA256 = "93d0dab6fbcf77a79ebc5e0d01f9f92faa2931e69947b8ff67d0bce243410382"
PDF_PAGE = 8
PRINTED_PAGE = 1183
NATIVE_SIZE = (671, 426)
PLOT_X_MIN, PLOT_X_MAX = 87, 607
PLOT_Y_MIN, PLOT_Y_MAX = 32, 374
X_TICKS = [(172, 5), (259, 10), (346, 15), (432, 20), (519, 25), (607, 30)]
Y_TICKS = [(32, 0), (89, -3), (146, -6), (203, -9), (260, -12), (317, -15)]
FS_PAPER_GSA = 63.0
FS_SIM_MHZ = 64.0
FIELDS = (
    "frequency_GHz", "s21_dB", "normalized_dB", "amplitude_ratio",
    "frequency_sim_MHz", "pixel_x", "pixel_y", "pixel_y_min", "pixel_y_max",
)


def locate_raster(document):
    """The blue trace is a raster below separate PDF annotation objects."""
    page = document[PDF_PAGE - 1]
    text = page.get_text()
    if DOI not in text or str(PRINTED_PAGE) not in text or "Fig. 7." not in text:
        raise ValueError("Expected the original Fig. 7 on PDF page 8 (printed page 1183).")
    matches = [item[0] for item in page.get_images() if tuple(item[2:4]) == NATIVE_SIZE]
    if len(matches) != 1:
        raise ValueError("Expected one 671-by-426 native Fig. 7 raster on the page.")
    xref = matches[0]
    pixmap = fitz.Pixmap(fitz.csRGB, fitz.Pixmap(document, xref))
    raster = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape((426, 671, 3))
    box = list(page.get_image_rects(xref)[0])
    return raster, xref, box


def calibrate_and_extract(raster):
    x_pixels, x_GHz = np.asarray(X_TICKS).T
    y_pixels, y_dB = np.asarray(Y_TICKS).T
    x_slope, x_intercept = np.polyfit(x_GHz, x_pixels, 1)
    y_slope, y_intercept = np.polyfit(y_dB, y_pixels, 1)
    x_error_pixels = max(abs(x_pixels - (x_slope * x_GHz + x_intercept)))
    y_error_pixels = max(abs(y_pixels - (y_slope * y_dB + y_intercept)))
    red, green, blue = raster.transpose((2, 0, 1))
    mask = (blue > 220) & (red < 40) & (green < 40)
    clip = mask[PLOT_Y_MIN:PLOT_Y_MAX + 1, PLOT_X_MIN:PLOT_X_MAX + 1]
    raw = []
    missing = []
    for x_index, column in enumerate(clip.T, start=PLOT_X_MIN):
        rows = np.flatnonzero(column) + PLOT_Y_MIN
        if len(rows) == 0:
            missing.append(x_index)
            continue
        # All occupied blue rows within a column are contiguous in this PDF.
        if len(rows) != rows[-1] - rows[0] + 1:
            raise ValueError(f"Ambiguous, disconnected blue trace at x={x_index}.")
        raw.append((x_index, np.median(rows), rows[0], rows[-1]))
    pixels = np.asarray(raw, dtype=float)
    frequencies = (pixels[:, 0] - x_intercept) / x_slope
    plotted_dB = (pixels[:, 1] - y_intercept) / y_slope
    reference_dB = plotted_dB[0]
    normalized_dB = plotted_dB - reference_dB
    result = np.column_stack((
        frequencies, plotted_dB, normalized_dB, 10 ** (normalized_dB / 20),
        frequencies * FS_SIM_MHZ / FS_PAPER_GSA, pixels,
    ))
    active_GHz = np.arange(1, 25) * FS_PAPER_GSA / FS_SIM_MHZ
    active = (frequencies >= active_GHz[0]) & (frequencies <= active_GHz[-1])
    if frequencies[0] > active_GHz[0] or frequencies[-1] < active_GHz[-1]:
        raise ValueError("Digitized trace does not cover all 24 active carriers.")
    half_span_dB = (pixels[:, 3] - pixels[:, 2] + 1) / (2 * abs(y_slope))
    details = {
        "horizontal_axis": {
            "label": "Frequency (GHz)", "labeled_ticks_x_pixel_GHz": X_TICKS,
            "pixel_per_GHz": x_slope, "origin_x_pixel": x_intercept,
            "max_anchor_residual_pixel": x_error_pixels,
            "estimated_coordinate_error_GHz": (x_error_pixels + 0.5) / abs(x_slope),
        },
        "vertical_axis": {
            "label": "S21 (dB)", "labeled_ticks_y_pixel_dB": Y_TICKS,
            "pixel_per_dB": y_slope, "origin_y_pixel": y_intercept,
            "max_anchor_residual_pixel": y_error_pixels,
            "definition": "End-to-end channel transmission magnitude in dB. "
            "After subtracting the low-frequency reference, amplitude ratio is 10^(normalized_dB/20).",
        },
        "low_frequency_reference": {
            "frequency_GHz": frequencies[0], "S21_dB": reference_dB,
            "assumption": "Treat the first visible near-DC sample as the unity reference. "
            "Assume a flat normalized response between DC and this sample when modeling DC. "
            "The flat extension to DC belongs to the model. The CSV starts at the first visible plotted sample.",
        },
        "trace_reading": {
            "native_pixel_origin": "Zero-based pixel-center coordinates from the top left",
            "inclusive_plot_bounds_xyxy": [PLOT_X_MIN, PLOT_Y_MIN, PLOT_X_MAX, PLOT_Y_MAX],
            "mask": "B > 220, R < 40, G < 40",
            "center": "Median blue row in each native column, with both occupied row endpoints retained",
            "columns_without_blue": missing,
            "read_error_basis": "The blue-column half thickness plus a half-pixel axis allowance "
            "describes raster reading precision. The original measurement uncertainty is unspecified. "
            "The low-frequency reference adds its own reading error to normalized values.",
            "reference_read_error_dB": half_span_dB[0] + 0.5 / abs(y_slope),
            "active_median_read_error_dB": np.median(half_span_dB[active]) + 0.5 / abs(y_slope),
            "active_max_read_error_dB": max(half_span_dB[active]) + 0.5 / abs(y_slope),
            "full_median_read_error_dB": np.median(half_span_dB) + 0.5 / abs(y_slope),
            "full_max_read_error_dB": max(half_span_dB) + 0.5 / abs(y_slope),
        },
        "native_column_count": len(result),
        "digitized_coverage_GHz": [frequencies[0], frequencies[-1]],
        "mapped_coverage_MHz": [result[0, 4], result[-1, 4]],
        "active_frequency_GHz": [active_GHz[0], active_GHz[-1]],
    }
    return result, details


def digitize(pdf_path, output_dir):
    pdf_sha = hashlib.sha256(pdf_path.read_bytes()).hexdigest()
    if pdf_sha != PDF_SHA256:
        raise ValueError("PDF bytes do not match the source used to calibrate the native axes.")
    with fitz.open(pdf_path) as document:
        raster, xref, box = locate_raster(document)
    points, details = calibrate_and_extract(raster)
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "Fig7_digitized.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(FIELDS)
        for point in points:
            writer.writerow(f"{value:.12g}" for value in point)
    provenance = {
        "citation": "K. Zhong et al., Experimental study of PAM-4, CAP-16, and DMT for "
        "100 Gb/s short reach optical transmission systems, Optics Express 23(2), 1176–1189 (2015)",
        "DOI": DOI, "figure": "Fig. 7", "printed_page": PRINTED_PAGE, "pdf_page": PDF_PAGE,
        "pdf_sha256": pdf_sha, "pdf_raster_xref": xref,
        "pdf_raster_bounding_box_points": box, "native_raster_pixels_width_height": NATIVE_SIZE,
        "native_raster_rgb_sha256": hashlib.sha256(raster.tobytes()).hexdigest(),
        "digitized_csv_sha256": hashlib.sha256(csv_path.read_bytes()).hexdigest(),
        "method": "Direct native raster extraction with PyMuPDF and labeled-grid calibration. "
        "The blue response has no vector path. PDF vector and bitmap annotations overlay "
        "the native plot, which retains the response under the 17 GHz dot and dash line.",
        "frequency_mapping": {
            "rule": "f_sim / Fs_sim = f_paper / Fs_paper",
            "paper_transmitter_AWG_GSa_per_s": FS_PAPER_GSA, "simulation_Fs_MHz": FS_SIM_MHZ,
            "paper_AWG_source": "Section 2.3, printed page 1180, reports the 63 GSa/s DMT transmitter AWG",
            "paper_measurement_source": "Section 3, printed page 1182, describes the discrete AWG sweep, "
            "80 GSa/s receiver scope and reported channel bandwidth of 17 GHz",
            "reported_bandwidth_GHz": 17.0,
            "reported_bandwidth_mapped_MHz": 17 * FS_SIM_MHZ / FS_PAPER_GSA,
        },
        **details,
    }
    (output_dir / "Fig7_provenance.json").write_text(
        json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="Original paper PDF supplied for Fig. 7 digitization.")
    parser.add_argument(
        "--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "evidence",
    )
    args = parser.parse_args()
    digitize(args.pdf, args.output_dir)


if __name__ == "__main__":
    main()
